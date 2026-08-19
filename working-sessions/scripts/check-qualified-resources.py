#!/usr/bin/env python3
"""Assert every `oc` call in every shipped script names its resource IN FULL.

WHY THIS EXISTS — a defect that shipped, and the log line that found it:

    Error from server (Forbidden): subscriptions.messaging.knative.dev "namespace-configuration-operator"
    is forbidden: ... cannot get resource "subscriptions" in API group "messaging.knative.dev"

`oc get subscription` had bound to the WRONG API GROUP. `subscriptions` is not a unique resource plural:
Knative Eventing serves one, OLM serves one, and several other operators do too. Which one a short name
resolves to is decided by API discovery, so it changes as CRDs are installed and removed — and these
scripts run in containers with HOME=/tmp and therefore a COLD discovery cache on every single run, so the
binding is not stable even between two runs of the same Job.

The first symptom was not an error at all. The approver read the mode with `2>/dev/null || true`, so the
misrouted Forbidden became an empty string, which the script read as "not Manual" and reported as
"OLM approves its own InstallPlans. Nothing to do." — exit 0, operator never installed, log pointing away
from the cause. Two independent bugs stacked: an ambiguous resource name, and a swallowed error. This
script covers the first; the second is fixed by branching on the exit status rather than discarding it.

WHAT IS CHECKED, and deliberately not:

  checked      the resource ARGUMENT of an `oc` verb, in every script this chart ships — that is, in the
               rendered output, so a script that only exists inside a ConfigMap value is covered exactly
               like a file. Comma-joined lists (`oc get a,b,c`) are checked element by element.
  not checked  shell variables holding the output of `oc get -o name`, which is already fully qualified
               (`subscription.operators.coreos.com/x`); prose in comments; and `kubectl`, which this chart
               does not use.

AMBIGUOUS BY CONSTRUCTION. The list below is not "resources someone found a clash for" — it is every
resource this chart touches whose plural is not reserved. A cluster is free to add a CRD tomorrow that
collides with any of them, so the rule is unconditional: name it in full, always. That is why this check
has no allowlist for "known safe" clusters.
"""

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

# Short name -> the fully qualified form to use instead. Keyed on every spelling `oc` accepts, including
# the singular and the documented short aliases, because all of them route through the same discovery.
MUST_QUALIFY = {
    "subscription": "subscriptions.operators.coreos.com",
    "subscriptions": "subscriptions.operators.coreos.com",
    "sub": "subscriptions.operators.coreos.com",
    "subs": "subscriptions.operators.coreos.com",
    "installplan": "installplans.operators.coreos.com",
    "installplans": "installplans.operators.coreos.com",
    "ip": "installplans.operators.coreos.com",
    "csv": "clusterserviceversions.operators.coreos.com",
    "csvs": "clusterserviceversions.operators.coreos.com",
    "clusterserviceversion": "clusterserviceversions.operators.coreos.com",
    "clusterserviceversions": "clusterserviceversions.operators.coreos.com",
    "operatorgroup": "operatorgroups.operators.coreos.com",
    "operatorgroups": "operatorgroups.operators.coreos.com",
    "og": "operatorgroups.operators.coreos.com",
    "namespaceconfig": "namespaceconfigs.redhatcop.redhat.io",
    "namespaceconfigs": "namespaceconfigs.redhatcop.redhat.io",
    "groupconfig": "groupconfigs.redhatcop.redhat.io",
    "groupconfigs": "groupconfigs.redhatcop.redhat.io",
    "userconfig": "userconfigs.redhatcop.redhat.io",
    "userconfigs": "userconfigs.redhatcop.redhat.io",
}

OC_CALL = re.compile(r"\boc\s+(?:get|patch|delete|wait|describe|label|annotate|apply|create)\s+"
                     r"(?:-[\w-]+(?:=\S+)?\s+)*"      # leading flags, e.g. -n ns, --ignore-not-found=true
                     r"([A-Za-z][\w.,-]*)")


def offenders(text, where):
    found = []
    for line_no, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        # A comment may legitimately discuss `oc get csv` in prose; the shipped COMMAND is what matters.
        if stripped.startswith("#"):
            continue
        for m in OC_CALL.finditer(line):
            arg = m.group(1)
            # `oc get "$ip"` — a variable, already qualified by `-o name`. Nothing to check.
            if arg.startswith("$"):
                continue
            for part in arg.split(","):
                if part in MUST_QUALIFY:
                    found.append((where, line_no, part, MUST_QUALIFY[part], line.strip()[:100]))
    return found


def render(chart):
    """Check the RENDER, so a script living inside a ConfigMap value is covered like a file."""
    proc = subprocess.run(["helm", "template", "qualified-resource-probe", chart],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("::error::helm template failed for %s\n%s" % (chart, proc.stderr))
    return proc.stdout


def main():
    charts = sorted(os.path.dirname(p) for p in glob.glob(os.path.join(REPO, "charts", "*", "Chart.yaml")))
    if not charts:
        sys.exit("::error::no charts found under charts/*/Chart.yaml")

    errors, scripts_seen = [], 0
    for chart in charts:
        raw = render(chart)
        for doc in yaml.safe_load_all(raw):
            if not doc or doc.get("kind") != "ConfigMap":
                continue
            for key, body in (doc.get("data") or {}).items():
                if not key.endswith(".sh"):
                    continue
                scripts_seen += 1
                errors += offenders(body, "%s/%s" % (doc["metadata"]["name"], key))
        # NOTES.txt is what an operator copy-pastes, so an ambiguous command there is a trap too.
        notes = os.path.join(chart, "templates", "NOTES.txt")
        if os.path.exists(notes):
            errors += offenders(open(notes).read(), os.path.relpath(notes, REPO))

    # EVERY SELECTOR MUST MATCH SOMETHING — a check that silently inspects nothing passes forever.
    if not scripts_seen:
        errors.append(("(no scripts)", 0, "-", "-",
                       "no ConfigMap key ending in .sh rendered from any chart, so this check inspected "
                       "nothing. Either the scripts moved out of ConfigMaps or the key naming changed."))

    if errors:
        for where, line_no, short, full, ctx in errors:
            print("::error::%s:%s uses the ambiguous resource name '%s' — write '%s'. `%s` can bind to "
                  "another API group entirely; measured on a live cluster, `oc get subscription` resolved "
                  "to subscriptions.messaging.knative.dev and returned Forbidden. Context: %s"
                  % (where, line_no, short, full, short, ctx))
        print("\nFAILED: %d ambiguous resource name(s)" % len(errors))
        return 1
    print("OK: all %d shipped script(s) name every OLM and policy resource in full." % scripts_seen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
