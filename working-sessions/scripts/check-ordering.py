#!/usr/bin/env python3
"""Assert this chart's install/uninstall ordering is DECLARED, not accidental.

Two orderings exist and they are separate mechanisms:

  helm.sh/hook-weight            orders the Jobs among themselves under plain Helm.
  argocd.argoproj.io/sync-wave   orders every resource under ArgoCD, and — the reason this
                                 script exists — ArgoCD DELETES in REVERSE wave order.

The delete direction is the one that bites. A policy CR must be deleted BEFORE the Subscription,
because deleting the CR runs a finalizer that revokes its RBAC objects, and the operator has to
still be running to execute it. Take the operator away first and the finalizer never runs: the CR
hangs on deletion and its RoleBindings stay live, granting access with no policy behind them.
Measured while building the sweeper — 3 CRs deleted against a restarting operator left 20
RoleBindings alive with no owner and no ownerReferences, so nothing would ever have collected them.

WHY A SCRIPT AND NOT INLINE CI. This logic outlived two rewrites of the workflow and was once lost
in an editing accident. In the repo it is reviewable, runnable locally before you push, and CI calls
it in one line.

HOW THIS STAYS TRUE WHEN TEMPLATES ARE ADDED — the whole design, because a validator that needs
updating every time the thing it validates changes is a validator that silently rots:

  1. DERIVE, NEVER LIST. Policy CRs are selected by API GROUP (redhatcop.redhat.io), so a new
     redhat-cop kind is covered the day it is added. Charts and values overlays are DISCOVERED by
     glob, so a new cluster overlay is checked without touching this file or CI.
  2. REQUIRE THE ANNOTATION, NEVER ASSUME A DEFAULT. Every document must carry an explicit sync-wave.
     ArgoCD treats a missing one as wave 0 — which is the Subscription's wave — so an omission is not
     a cosmetic gap, it is an ordering bug that reads as fine. This is checked in the template SOURCE
     as well as in the render, because a render only ever sees the templates the current values switch
     on: `00-namespace.yaml` is gated behind `createNamespace` and no combination here reaches it.
     Reading the files needs no values, so a new template cannot be forgotten and a gated one cannot
     hide.
  3. EVERY SELECTOR MUST MATCH SOMETHING. A check whose selector quietly matches nothing passes
     forever while testing nothing, which is worse than having no check at all. Each lookup below
     asserts it found what it was looking for, so renaming a component fails loudly.

Usage:
    working-sessions/scripts/check-ordering.py            # every chart, every overlay
    working-sessions/scripts/check-ordering.py --chart charts/namespace-configuration-operator
"""

import argparse
import glob
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

WAVE = "argocd.argoproj.io/sync-wave"
WEIGHT = "helm.sh/hook-weight"
HOOK = "helm.sh/hook"
COMPONENT = "app.kubernetes.io/component"

# The API group that owns the policy CRs. A GROUP and not a list of kinds, so a NamespaceConfig,
# a GroupConfig, or any future redhat-cop kind is picked up without editing this script.
POLICY_GROUP = "redhatcop.redhat.io"

# The component label of the sweep that must run after the policy CRs have settled. Matched on the
# LABEL rather than the resource name, which is release-name dependent.
SWEEPER = "orphan-sweeper"


def check_template_sources(chart, verbose=True):
    """Every document in every template file must declare a wave, WHATEVER the values say.

    This is deliberately a SOURCE check and not a render check, because rendering can only ever see
    the templates the current values switch on. `00-namespace.yaml` is the live example: it is gated
    behind `createNamespace`, which is false in both values.yaml and the crc overlay, so no rendered
    combination reaches it. It does declare a wave — but nothing would have told us if it stopped.
    Reading the files needs no values at all, so a gated template is covered exactly like any other.
    """
    errors, docs_seen = [], 0
    root = os.path.join(chart, "templates")
    for path in sorted(glob.glob(os.path.join(root, "**", "*.y*ml"), recursive=True)):
        # A leading underscore is a partial, not a manifest — Helm never emits it.
        if os.path.basename(path).startswith("_"):
            continue
        text = open(path).read()
        # Split textually on the YAML document separator. These files contain Go actions and are NOT
        # parseable as YAML until the operator has rendered them, so a parser is not an option here.
        for i, chunk in enumerate(re.split(r"(?m)^---\s*$", text)):
            if not re.search(r"(?m)^kind:\s*\S", chunk):
                continue
            docs_seen += 1
            # An annotation LINE, not a substring. `WAVE in chunk` was satisfied by the key merely
            # appearing in a comment — so commenting the annotation out passed this check, and for a
            # gated template no render exists to catch it. Anchored to line start plus indentation,
            # which a `#` before the key cannot match.
            if not re.search(r"(?m)^\s*%s\s*:" % re.escape(WAVE), chunk):
                kind = re.search(r"(?m)^kind:\s*(\S+)", chunk).group(1)
                errors.append("%s (document %d, kind %s) declares no %s. ArgoCD would read it as "
                              "wave 0 — the Subscription's wave — so it could be deleted after the "
                              "operator it depends on."
                              % (os.path.relpath(path, REPO), i + 1, kind, WAVE))
    if not docs_seen:
        errors.append("no manifest documents found under %s — this check has stopped covering "
                      "anything" % os.path.relpath(root, REPO))
    elif verbose:
        print("    template sources: %d document(s) across %d file(s), every one declaring a wave"
              % (docs_seen, len(set(glob.glob(os.path.join(root, "**", "*.y*ml"), recursive=True)))))
    return errors


def render(chart, values):
    cmd = ["helm", "template", "release-under-test", chart]
    for v in values:
        cmd += ["-f", v]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("::error::helm template failed for %s\n%s" % (chart, proc.stderr))
    return [d for d in yaml.safe_load_all(proc.stdout) if d]


def group_of(doc):
    api = doc.get("apiVersion", "")
    return api.split("/")[0] if "/" in api else "core"


def annotations(doc):
    return (doc.get("metadata") or {}).get("annotations") or {}


def labels(doc):
    return (doc.get("metadata") or {}).get("labels") or {}


def check(chart, values, verbose=True):
    """Return (errors, saw_sweeper) for one rendered combination."""
    docs = render(chart, values)
    label = "%s [%s]" % (os.path.basename(chart), ", ".join(os.path.basename(v) for v in values) or "defaults")
    errors = []

    if verbose:
        print("\n=== %s — %d resources" % (label, len(docs)))
        print("    %-22s %-44s %5s %s" % ("KIND", "NAME", "WAVE", "HOOK-WEIGHT"))

    unwaved, policies, hook_weights, subscription = [], [], {}, None
    # The sweeper's Job is separated from its own prerequisites deliberately. They pull in OPPOSITE
    # directions: the Job must run AFTER the policy CRs it inspects, while its ServiceAccount,
    # ConfigMap and RBAC must exist BEFORE it starts. Selecting on the component label alone
    # conflates the two — which is how the first version of this script "found" four failures in a
    # chart that was correct.
    sweeper_job, sweeper_prereqs = [], []

    for doc in docs:
        kind = doc["kind"]
        name = (doc.get("metadata") or {}).get("name", "<unnamed>")
        ann = annotations(doc)
        raw_wave, raw_weight = ann.get(WAVE), ann.get(WEIGHT)

        if verbose:
            print("    %-22s %-44s %5s %s" % (kind, name[:44], raw_wave if raw_wave is not None else "MISSING",
                                              raw_weight if raw_weight is not None else "-"))

        # RULE 2. Absent is not neutral — ArgoCD reads it as wave 0, the Subscription's own wave.
        if raw_wave is None:
            unwaved.append("%s/%s" % (kind, name))
            continue
        wave = int(raw_wave)

        if group_of(doc) == POLICY_GROUP:
            policies.append((kind, name, wave))
        if kind == "Subscription":
            subscription = (name, wave)
        if labels(doc).get(COMPONENT) == SWEEPER:
            (sweeper_job if kind == "Job" else sweeper_prereqs).append((kind, name, wave))
        # Helm orders hooks by weight, then falls back to NAME. Two hooks sharing a weight are
        # therefore ordered by accident, and this chart's hooks depend on each other in sequence.
        if HOOK in ann:
            if raw_weight is None:
                errors.append("%s: %s/%s is a Helm hook with no %s" % (label, kind, name, WEIGHT))
            else:
                hook_weights.setdefault(int(raw_weight), []).append(
                    ("%s/%s" % (kind, name), labels(doc).get(COMPONENT) == SWEEPER, ann[HOOK]))

    if unwaved:
        errors.append("%s: %d resource(s) carry no %s, which ArgoCD reads as wave 0 — the "
                      "Subscription's wave: %s" % (label, len(unwaved), WAVE, ", ".join(unwaved)))

    # RULE 3. Both of these assert the selector matched, so a rename cannot turn the check into a
    # no-op that keeps reporting success.
    if subscription is None:
        errors.append("%s: no Subscription rendered — this check cannot verify delete ordering "
                      "without one, so it is failing rather than passing vacuously" % label)
    if not policies:
        errors.append("%s: no %s resources rendered. If every policy is genuinely disabled this "
                      "combination should not be checked; otherwise the API group above is stale"
                      % (label, POLICY_GROUP))

    # THE ASSERTION THIS SCRIPT EXISTS FOR. Higher wave = deleted earlier.
    if subscription and policies:
        sub_name, sub_wave = subscription
        for kind, name, wave in policies:
            if wave <= sub_wave:
                errors.append("%s: %s/%s is at wave %d, at or below the Subscription (%s, wave %d). "
                              "ArgoCD deletes in reverse wave order, so the operator would be removed "
                              "before this CR's finalizer could revoke its RBAC — leaving live grants "
                              "with no policy behind them." % (label, kind, name, wave, sub_name, sub_wave))

    # The sweep cleans up what pruning leaves behind, so the JOB has to be applied after the CRs it
    # inspects. Skipped, with a note, when the sweeper is switched off in this combination.
    if sweeper_job and policies:
        newest_policy = max(w for _, _, w in policies)
        for kind, name, wave in sweeper_job:
            if wave <= newest_policy:
                errors.append("%s: sweeper %s/%s is at wave %d, not after the newest policy CR "
                              "(wave %d) — it would inspect the previous state and miss the orphans "
                              "this sync just created." % (label, kind, name, wave, newest_policy))
    # And its prerequisites the other way round: a Job whose ServiceAccount or ConfigMap arrives in a
    # later wave cannot start, and under ArgoCD that is a stuck sync rather than an obvious error.
    if sweeper_job and sweeper_prereqs:
        job_wave = min(w for _, _, w in sweeper_job)
        for kind, name, wave in sweeper_prereqs:
            if wave > job_wave:
                errors.append("%s: sweeper prerequisite %s/%s is at wave %d, AFTER the sweeper Job "
                              "(wave %d) — the Job cannot mount or authenticate with something that "
                              "does not exist yet." % (label, kind, name, wave, job_wave))
    if verbose and not sweeper_job:
        print("    (no %s Job in this combination — sweeper assertions skipped)" % SWEEPER)

    for weight, holders in sorted(hook_weights.items()):
        if len(holders) > 1:
            errors.append("%s: hooks share %s=%d, so Helm falls back to name order and their "
                          "sequence is accidental: %s" % (label, WEIGHT, weight,
                                                          ", ".join(h for h, _, _ in holders)))

    # Uniqueness above cannot see DIRECTION. Under plain Helm the hooks run in weight order, and the
    # sweep inspects the state every other hook produces — the operator install included — so it must
    # be the LAST hook of its event. Weighted below the InstallPlan approver it would run before the
    # policy CRDs exist: `oc get namespaceconfig` fails, the Job fails, and the install fails with it.
    # Only hooks sharing one of the sweeper's events are compared; a pre-install hook is a different
    # queue and its weight is not on this axis.
    sweeper_weight, sweeper_events = None, set()
    for weight, holders in hook_weights.items():
        for _, is_sweeper, events in holders:
            if is_sweeper:
                sweeper_weight = weight
                sweeper_events = set(events.replace(" ", "").split(","))
    if sweeper_weight is not None:
        for weight, holders in sorted(hook_weights.items()):
            for holder, is_sweeper, events in holders:
                if is_sweeper or not (set(events.replace(" ", "").split(",")) & sweeper_events):
                    continue
                if weight >= sweeper_weight:
                    errors.append("%s: hook %s has %s=%d, at or above the sweeper's (%d). The sweep "
                                  "must run after every hook that installs or configures the operator, "
                                  "or it inspects a cluster where the policy CRDs do not exist yet."
                                  % (label, holder, WEIGHT, weight, sweeper_weight))

    if verbose and subscription:
        print("    Subscription wave=%d; policy CRs at %s; hook weights %s"
              % (subscription[1], sorted({w for _, _, w in policies}) or "none",
                 sorted(hook_weights) or "none"))

    return errors, bool(sweeper_job)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chart", action="append", help="chart path; repeatable. Default: every chart under charts/")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    # RULE 1. Charts and overlays are DISCOVERED. Adding charts/<new>/ or a new <cluster>-values.yaml
    # brings it under this check with no edit here and no edit in CI.
    charts = args.chart or sorted(os.path.dirname(p) for p in glob.glob(os.path.join(REPO, "charts", "*", "Chart.yaml")))
    if not charts:
        sys.exit("::error::no charts found under charts/*/Chart.yaml")

    errors, sweeper_seen_anywhere = [], False
    for chart in charts:
        if not args.quiet:
            print("\n=== %s — template sources" % os.path.basename(chart))
        # Source first: it covers templates that no values combination switches on.
        errors += check_template_sources(chart, verbose=not args.quiet)
        # values.yaml is applied by Helm on its own; every OTHER values file is an overlay to check
        # on top of it, which is exactly how it is used at install time.
        overlays = [p for p in sorted(glob.glob(os.path.join(chart, "*values*.y*ml")))
                    if os.path.basename(p) != "values.yaml"]
        for values in [[]] + [[o] for o in overlays]:
            errs, saw = check(chart, values, verbose=not args.quiet)
            errors += errs
            sweeper_seen_anywhere |= saw

    # RULE 3 again, across every combination: if no render anywhere produced a sweeper resource, the
    # component label was renamed and that assertion has become dead code.
    if not sweeper_seen_anywhere:
        errors.append("no Job labelled %s=%s in ANY combination — either the sweeper is disabled "
                      "everywhere or the label was renamed, and the sweeper ordering assertions have "
                      "become dead code that will keep reporting success" % (COMPONENT, SWEEPER))

    print()
    if errors:
        for e in errors:
            print("::error::%s" % e)
        print("\nFAILED: %d ordering problem(s)" % len(errors))
        return 1
    print("OK: every template document declares a wave, policy CRs are deleted before the "
          "Subscription, the sweep runs after them, and no two hooks share a weight.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
