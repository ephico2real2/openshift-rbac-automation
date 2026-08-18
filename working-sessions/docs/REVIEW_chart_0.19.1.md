# Review — chart 0.19.1 (branch `feat/oud-group-multiple-policies`)

**Reviewer: Fable 5. Arbiter: Claude.** Fable writes findings here. Claude accepts or rejects each one
against the use case below, and only ACCEPTED items get implemented.

## The use case, so a finding can be judged against it

A Helm chart installs the redhat-cop Namespace Configuration Operator via OLM **and** ships the RBAC
policies. Two template engines share `{{ }}`: Helm renders at install; the **operator** renders each
`objectTemplate` later, once per matching namespace or group, where `.Name` / `.Labels` are ITS context.
Operator expressions are therefore built as **strings** so Helm cannot evaluate them — if Helm does
evaluate one, it tests an undefined `.Name`, renders the object away, and **reports success**.

- Managed by ArgoCD eventually, so install and uninstall must be **one-shot and self-healing**.
- The 5 policy CRs are Helm's; the ~42 RoleBindings/ClusterRoleBindings/Roles are the **operator's** and
  have **no ownerReferences** — nothing garbage-collects them. Hence the orphan sweeper.
- The operator injects `excludedPaths: [.metadata, .status, .spec.replicas]`, so **metadata edits never
  reach objects that already exist**. Spec changes do propagate.
- `roleRef` is **immutable** in Kubernetes.
- Live cluster: CRC, release `nco`, rev 19, chart 0.19.1, 42 objects, 5 CRs.

**Constraints on any proposed fix — a finding that violates these is out of scope:**

1. **No clever design, no complicated logic.** Simplest thing that is correct.
2. **Never `| quote` a built operator expression** — the operator renders Go-template first, parses YAML
   second, so `\"` breaks the parse. Quotes go in as `printf` arguments.
3. **`#` is a YAML comment, not a Helm comment.** An action inside one IS evaluated.
4. **No heredocs and no column-0 closing quotes inside the sweeper script** — both end the enclosing
   YAML block scalar and break the ConfigMap.
5. **Nothing hardcoded in CI** that values.yaml owns (label keys, policy names, counts). Derive it.
6. **Comments say WHY, not WHAT.** Condensing must not delete the reasoning.
7. `/metrics`-style public-by-decision choices and the sweeper's broad ClusterRole are **accepted
   trade-offs**, already argued in the templates. Re-litigating them is not a finding.

## Files in scope

```
charts/namespace-configuration-operator/templates/14-orphan-sweeper-script.yaml   the sweeper (bash in a ConfigMap)
charts/namespace-configuration-operator/templates/15-orphan-sweeper-rbac.yaml     its SA + ClusterRole
charts/namespace-configuration-operator/templates/rbac-policies/10..13*.yaml      the four policies
charts/namespace-configuration-operator/values.yaml                               ~700 lines, mostly comment
working-sessions/scripts/check-ordering.py                                        the CI ordering check
working-sessions/docs/labels-and-annotations.md                                   the label contract
```

## Claims to verify — one verdict each: CONFIRMED / REFUTED / FIX-INADEQUATE

Prefer **refutation**. "Cannot refute" is fine only if you say what you actually checked.

**Sweeper (14, 15)** — 0.19.1 just fixed a bug where `! oc get role ... >/dev/null 2>&1` treated
*Forbidden* as *not found*, so a missing `get` verb made every managed RoleBinding look dangling and it
deleted all of them on every sync. Counts matched afterwards because the operator rebuilt them, so it
hid. With that in mind:

- **S1** Any REMAINING place in the script where a failure or empty result is read as a decision to
  delete, or as "nothing to do". Include the `IFS` juggling and the `while read` subshell counters.
- **S2** `ORPHAN_LIMIT` is checked for the first sweep only. Is the second sweep (dangling Roles)
  unbounded, and does that matter given it deletes only on a definite absence?
- **S3** The second sweep does one `oc get role` per binding. At 42 objects that is fine; state where it
  stops being fine and whether the simplest fix (one `oc get role -A` up front) is worth it.
- **S4** The ClusterRole now grants `get,list,delete` on roles/rolebindings/clusterrolebindings
  cluster-wide. Given constraint 7, is `get` on `roles` alone sufficient, or is anything now unused?
- **S5** `DRY_RUN=true` — verify BOTH sweeps genuinely delete nothing and still report what they would do.

**Policies (10–13)**

- **P1** Any operator expression Helm could evaluate, or any `| quote` on one.
- **P2** `12`'s `$group` comes from `index .Labels "<key>"`. What renders if a matching namespace lacks
  that label — an empty subject name, a rejected object, or a silent no-op? State which.
- **P3** Two `oudGroup.policies` keys sharing a `labelKey` or a `roleName`: what actually collides now
  that the duplicate guard was removed? (RoleBindings are per-namespace; Roles coexist.)

**Ordering check**

- **K1** A wave ordering that is wrong but PASSES: find one the four assertions miss.
- **K2** The source pass splits on `^---$` textually. Find a valid template shape it mis-parses.

**Comments and docs — the condensing pass**

- **D1** Name the specific comment blocks that state WHAT the code already says, or repeat a fact stated
  elsewhere, and give the condensed replacement text. Preserve every WHY, every measured number, and
  every trap. Say how many lines each saves.
- **D2** Any comment or doc line that is now **factually wrong** after 0.19.1 (especially anything
  implying Helm cannot override, or that a roleName change needs a manual step).

## Required form for every finding

````
> **Fable:** S1 — CONFIRMED
> **Where:** file:line or symbol
> **Trigger:** the concrete state or input, not "could race"
> **Consequence:** what a reader of `oc get` would believe that is false
> **Fix (complete, ready to apply):**
> ```bash
> # the whole replacement block, matching the surrounding comment style
> ```
> **Proof:** the command you ran and its output
````

Then Claude appends `**Claude: ACCEPT**` or `**Claude: REJECT** — reason`.

Findings must carry a **complete** replacement block, not "add a check". Measure rather than reason:
`helm lint`, `helm template`, `oc auth can-i --as=<sa>`, a scratch script. If you assert a behaviour,
show the command and its output.

---

## Fable — pass 1

All behavioural claims below were measured: `helm lint`/`helm template` on the chart, the real
rendered script run against a stub `oc` (harness:
`/private/tmp/claude-501/-Users-olasumbo-gitRepos-group-sync-dashboard/325dfd2f-469e-4bd4-b279-331704911184/scratchpad/sweep-harness/`),
`check-ordering.py` against mutated chart copies, and read-only `oc` (+ `--as=` impersonation)
against the live CRC cluster (5 CRs, 42 managed objects, verified). Nothing was written to the cluster.

---

> **Fable:** S1 — CONFIRMED (two remaining instances; the `IFS` juggling and the `while read` counters are clean — measured, see Proof)
> **Where:** `charts/namespace-configuration-operator/templates/14-orphan-sweeper-script.yaml` — (a) all five `$( oc … 2>&1 )` capture sites: lines 53, 55, 85–88, 173–176, 183; (b) line 40 `: "${MANAGED_BY:?}" "${DRY_RUN:?}"` + line 64 `ORPHAN_LIMIT="${ORPHAN_LIMIT:-0}"`.
> **Trigger (a):** `oc` prints warnings to STDERR **with rc=0** — this very cluster does it today (`oc auth can-i … ` printed `Warning: resource 'clusterrolebindings' is not namespace scoped…` on rc=0; client/server version-skew and API deprecation warnings behave the same, and the Job's image `openshift/cli:latest` skewing from the server is an ordinary state). Because every capture merges stderr into the parsed data:
> - On the named-role probe, an **absent** Role plus a warning gives rc=0 with **non-empty** `$ROLEOUT` → read as *exists* → the dangling binding is kept and the run logs `no rolebinding points at a missing Role`. The roleName self-heal — the whole point of 0.19.0 — is silently un-fixed, in exactly the 0.19.1 defect shape (a non-answer read as an answer), in the safe-looking direction this time.
> - On the list calls, the warning line is parsed as a data row: it becomes a **phantom orphan candidate** per kind, inflates `COUNT`, and in a live run the sweep issues `oc delete rolebinding "Warning: resource …"` — an invalid name the API refuses, which aborts the sync mid-sweep.
> **Trigger (b):** run the script with `ORPHAN_LIMIT` unset (a runbook `oc exec`, a debug pod — the `:?` guard demands the other two vars but not this one) → defaults to 0 → **no cap**. Run it with a malformed value (`ORPHAN_LIMIT=abc`): `[ … -gt … ]` errors, the error is exempt inside the `&&` list, and the cap is **silently skipped** — measured: 3 orphans deleted, exit 0, one stray `integer expression expected` line.
> **Consequence:** a reader of the Job log believes (a) "no rolebinding points at a missing Role" when a dangling, nothing-granting binding exists — or believes the cluster contains an orphan literally named `Warning: …`; and (b) believes the `limit: 25` blast-radius guard promised by values.yaml protected the run, when it was absent.
> **Fix (complete, ready to apply):** the whole script body under `sweep-orphans.sh: |` (everything down to `{{- end }}`), re-indented four spaces. Deltas from current: stderr is **never captured into parsed data** (it flows to the pod log, where the API's message still lands right above each abort); `ORPHAN_LIMIT` joins the `:?` guard and is checked numeric; the second sweep's per-binding log says `would delete` under dry run (see S5). Round-trip verified: this body, spliced into the ConfigMap, passes `helm lint`, renders byte-identical back out, and passes every harness scenario.
> ```bash
> #!/bin/bash
> set -euo pipefail
>
> log()  { printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
> fail() { log "ERROR: $*"; exit 1; }
>
> # ORPHAN_LIMIT is required alongside the other two: an UNSET limit used to default to 0, which means
> # "no cap" — so running this script outside the Job (a runbook, a debug pod) silently discarded the
> # blast-radius guard values.yaml promises. Required-and-numeric makes 0 an explicit choice, never an
> # accident of a missing env var or a typo'd value.
> : "${MANAGED_BY:?}" "${DRY_RUN:?}" "${ORPHAN_LIMIT:?}"
> case "$ORPHAN_LIMIT" in ''|*[!0-9]*) fail "ORPHAN_LIMIT must be a whole number (0 disables the cap), got '${ORPHAN_LIMIT}' — refusing to run without a working blast-radius guard";; esac
>
> log "sweeping objects labelled app.kubernetes.io/managed-by=${MANAGED_BY} whose owning CR is gone"
> [ "$DRY_RUN" = "true" ] && log "DRY RUN: nothing will be deleted"
>
> # Which policy CRs currently exist, in ANY state. A CR mid-deletion still counts as existing: its
> # finalizer is running and revoking its own objects, so sweeping underneath it would be racing the
> # operator for no benefit.
> #
> # A FAILED LOOKUP IS NOT AN EMPTY RESULT. These used to end in `2>/dev/null || true`, which turned
> # any API error into "no policy CRs exist" — and every managed object would then look orphaned.
> # ORPHAN_LIMIT would have caught the resulting mass deletion, but a limit is a backstop, not a
> # diagnosis. Abort instead; the API's own message goes to the log on stderr, just above the abort.
> #
> # STDOUT ONLY on every capture in this script, deliberately: oc prints warnings to STDERR with
> # rc=0, and a warning merged into a parsed result becomes a phantom data row — or, on the named-role
> # probe below, makes an ABSENT Role read as PRESENT. Anything oc says that is not data belongs in
> # the pod log, not in a variable.
> NCS="$(oc get namespaceconfig -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')" \
>   || fail "cannot list namespaceconfigs, so which CRs are alive is unknown and NOTHING will be swept — the API's error is printed above"
> GCS="$(oc get groupconfig -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')" \
>   || fail "cannot list groupconfigs, so which CRs are alive is unknown and NOTHING will be swept — the API's error is printed above"
> EXISTING="$(printf '%s\n%s\n' "$NCS" "$GCS" | sed '/^$/d')"
> log "live policy CRs: $(printf '%s' "$EXISTING" | tr '\n' ' ')"
>
> # The cap below guards against a run whose CR list is legitimately EMPTY or legitimately WRONG for
> # the objects on the cluster — every flag switched off by a bad -f upgrade, or a label-value
> # migration where existing objects still carry a config-source no CR matches (measured at 0.16.0:
> # 36 stale objects, and this cap turned the mass revocation into a failed sync). A failed lookup no
> # longer reaches here at all — it aborts above.
>
> # NO HEREDOC HERE, deliberately. A heredoc terminator has to sit at the start of its line, which
> # ends the enclosing YAML block scalar and makes this ConfigMap unparseable — `helm lint` catches it
> # as "could not find expected ':'". Lines are split with parameter expansion instead, which also
> # keeps the loop in the current shell so the counters below actually accumulate (a `... | while read`
> # pipeline would run in a subshell and lose them).
> KEPT=0; CANDIDATES=""
> # $'\n' rather than a literal two-line string: a closing quote at column 0 would end the YAML block
> # scalar this script lives in, which is the same trap the heredoc hit.
> NL=$'\n'
> for kind in rolebinding clusterrolebinding role; do
>   # -A is invalid for a cluster-scoped kind, so the flag is chosen per kind.
>   scope="-A"; [ "$kind" = "clusterrolebinding" ] && scope=""
>   # READS THE config-source LABEL, not the old source-{namespace,group}config annotations. As of
>   # 0.16.0 there is ONE provenance key and it is a label, so this is a single field lookup instead of
>   # two concatenated annotations — and it is the same key a human would select on, so the sweeper and
>   # the runbook cannot disagree about what owns an object.
>   # Same rule as the CR lookup above: an error must not masquerade as an empty result. Here the
>   # consequence is the opposite direction — a swallowed failure means a genuine orphan is missed and
>   # the log still says "no orphans found" — which is why it aborts rather than reporting a clean run.
>   RAW="$(oc get "$kind" $scope -l "app.kubernetes.io/managed-by=${MANAGED_BY}" \
>            -o jsonpath="{range .items[*]}{.metadata.namespace}|{.metadata.name}|{.metadata.labels.rbac\.ocp\.io/config-source}{'\n'}{end}")" \
>     || fail "cannot list ${kind}, so this sweep would report a clean run without having checked — the API's error is printed above"
>   OLDIFS="$IFS"; IFS="$NL"
>   for line in $RAW; do
>     IFS="$OLDIFS"
>     [ -z "$line" ] && { IFS="$NL"; continue; }
>     ns="${line%%|*}"
>     rest="${line#*|}"
>     name="${rest%%|*}"
>     owner="${rest#*|}"
>     if [ -z "$name" ]; then IFS="$NL"; continue; fi
>     # No config-source label: not ours to reason about, left alone deliberately. The sweeper only
>     # ever acts on an object that NAMES the policy which should own it.
>     if [ -z "$owner" ]; then KEPT=$((KEPT+1)); IFS="$NL"; continue; fi
>     if printf '%s\n' "$EXISTING" | grep -qxF "$owner"; then
>       KEPT=$((KEPT+1)); IFS="$NL"; continue
>     fi
>     CANDIDATES="${CANDIDATES}${kind}|${ns}|${name}|${owner}${NL}"
>     IFS="$NL"
>   done
>   IFS="$OLDIFS"
> done
>
> COUNT="$(printf '%s' "$CANDIDATES" | sed '/^$/d' | wc -l | tr -d ' ')"
> # NO EARLY EXIT HERE. The dangling-Role sweep below is independent of this one and must run even when
> # every object has a live owner — a roleName change leaves bindings dangling while their CR is
> # perfectly healthy, so an `exit 0` on "no orphans" would skip exactly the case it needs to catch.
> if [ "$COUNT" -eq 0 ]; then
>   log "no orphans found (${KEPT} objects checked, all owned by a live CR)"
> fi
>
> if [ "$COUNT" -gt 0 ] && [ "$ORPHAN_LIMIT" -gt 0 ] && [ "$COUNT" -gt "$ORPHAN_LIMIT" ]; then
>   log "found ${COUNT} orphan candidates:"
>   printf '%s' "$CANDIDATES" | sed '/^$/d' | sed 's/^/    /'
>   fail "refusing to delete ${COUNT} objects, which exceeds orphanSweeper.limit=${ORPHAN_LIMIT}. That many at once usually means the policy-CR list is wrong for what is on the cluster — every policy switched off by a bad upgrade, or a label-value migration — rather than the objects genuinely being orphaned, and deleting them would revoke everything this chart grants. Check 'oc get namespaceconfig,groupconfig' returns your policies, then re-run or raise the limit."
> fi
>
> if [ "$COUNT" -gt 0 ]; then
> log "found ${COUNT} orphaned object(s); their owning CR does not exist:"
> printf '%s' "$CANDIDATES" | sed '/^$/d' | while IFS='|' read -r kind ns name owner; do
>   log "  ${kind} ${ns:-<cluster>}/${name}  ->  missing CR '${owner}'"
> done
>
> if [ "$DRY_RUN" = "true" ]; then
>   log "DRY RUN: leaving all ${COUNT} in place"
> else
>
> printf '%s' "$CANDIDATES" | sed '/^$/d' | while IFS='|' read -r kind ns name owner; do
>   if [ -n "$ns" ]; then
>     oc delete "$kind" "$name" -n "$ns" --ignore-not-found 2>&1 | sed 's/^/    /'
>   else
>     oc delete "$kind" "$name" --ignore-not-found 2>&1 | sed 's/^/    /'
>   fi
> done
> log "swept ${COUNT} orphaned object(s); ${KEPT} left in place under a live CR"
> fi
> fi
> # --- SECOND SWEEP: RoleBindings whose Role no longer exists -----------------------------
> # Renaming a policy's roleName cannot be applied in place: roleRef is IMMUTABLE in Kubernetes, so the
> # operator creates the new Role, REMOVES the old one, and then fails forever trying to repoint the
> # binding — "cannot change roleRef" — while the CR still logs "resources processed successfully". The
> # binding is left referencing a Role that is gone, which grants nothing and reports nothing.
> #
> # Deleting the binding is the fix, because the operator recreates it from the CR with the correct
> # roleRef on the next reconcile. That makes a roleName change self-healing on a plain `helm upgrade`,
> # with no manual CR delete.
> #
> # SCOPED TO roleRef kind=Role ON PURPOSE. A Role is created by the same policy that binds it, so a
> # missing target means a rename. A ClusterRole is EXTERNAL — customGroupConfig deliberately binds
> # roles this chart does not create — and one may be legitimately absent while someone applies it.
> # Deleting those bindings would fight the operator in a delete/recreate loop, so they are left alone
> # and remain the documented silent-dangle case.
> # ABSENT AND UNREADABLE ARE DIFFERENT ANSWERS, and conflating them is how this sweep deleted three
> # healthy RoleBindings on a no-op upgrade. The test was `! oc get role ... >/dev/null 2>&1`, which is
> # true for "not found" AND for "Forbidden" — and the ClusterRole granted list+delete on roles but not
> # `get`, so EVERY managed RoleBinding looked dangling on EVERY sync. The operator rebuilt each one
> # within a second or two, so the object counts matched afterwards and nothing in `oc get` showed it.
> #
> # `--ignore-not-found` gives the three-way answer this decision actually needs. Measured on this
> # cluster before relying on it:
> #   absent     rc=0, empty output                      -> the rename case, safe to delete
> #   exists     rc=0, "role.rbac.../<name>"             -> leave alone
> #   forbidden  rc=1, "Error from server (Forbidden)"   -> UNKNOWN, must not delete
> # Deleting RBAC on an unknown is the one outcome a sweeper must never produce, so rc!=0 aborts.
> # STDOUT ONLY, like every capture above: oc warnings arrive on stderr with rc=0, and one captured
> # here would make an absent Role read as present — the sweep would keep the dangling binding and
> # report a clean run, silently un-fixing the roleName self-heal.
> DANGLING=0
> # Same no-heredoc rule as the sweep above: a terminator at column 0 would end this YAML block scalar.
> RAWRB="$(oc get rolebinding -A -l "app.kubernetes.io/managed-by=${MANAGED_BY}" \
>            -o jsonpath="{range .items[?(@.roleRef.kind=='Role')]}{.metadata.namespace}|{.metadata.name}|{.roleRef.name}{'\n'}{end}")" \
>   || fail "cannot list rolebindings for the dangling-Role sweep — the API's error is printed above"
> OLDIFS="$IFS"; IFS="$NL"
> for line in $RAWRB; do
>   IFS="$OLDIFS"
>   if [ -n "$line" ]; then
>     dns="${line%%|*}"; drest="${line#*|}"; dname="${drest%%|*}"; drole="${drest#*|}"
>     if [ -n "$dname" ] && [ -n "$drole" ]; then
>       if ROLEOUT="$(oc get role "$drole" -n "$dns" --ignore-not-found -o name)"; then
>         if [ -z "$ROLEOUT" ]; then
>           if [ "$DRY_RUN" = "true" ]; then
>             log "  rolebinding ${dns}/${dname} -> Role/${drole} does not exist; would delete so the operator rebuilds it"
>           else
>             log "  rolebinding ${dns}/${dname} -> Role/${drole} does not exist; deleting so the operator rebuilds it"
>             oc delete rolebinding "$dname" -n "$dns" --ignore-not-found 2>&1 | sed 's/^/    /'
>           fi
>           DANGLING=$((DANGLING+1))
>         fi
>       else
>         fail "cannot determine whether Role/${drole} exists in ${dns}, so ${dns}/${dname} is being LEFT ALONE rather than deleted on a guess. Most likely the sweeper's ClusterRole is missing 'get' on roles — the API's error is printed above"
>       fi
>     fi
>   fi
>   IFS="$NL"
> done
> IFS="$OLDIFS"
> if [ "$DANGLING" -gt 0 ]; then
>   log "found ${DANGLING} rolebinding(s) pointing at a missing Role$([ "$DRY_RUN" = "true" ] && echo ' (dry run: left in place)')"
> else
>   log "no rolebinding points at a missing Role"
> fi
> ```
> **Proof:** live cluster shows warnings-on-rc0 are real (`oc auth can-i get clusterrolebindings --as=…` → `Warning: resource 'clusterrolebindings' is not namespace scoped…` + `yes`, rc=0). Harness, real rendered script vs stub oc:
> - role ABSENT + stderr warning on the rc=0 probe → `no rolebinding points at a missing Role`, exit 0, zero deletes (dangling binding silently kept);
> - warning on the list calls → `found 3 orphaned object(s)` and three real `oc delete rolebinding "Warning: resource …"` invocations;
> - `ORPHAN_LIMIT` unset, 30 orphans, empty CR list → all 30 deleted, exit 0; `ORPHAN_LIMIT=abc` → `[: abc: integer expression expected`, cap skipped, 3 deleted, exit 0.
> Fixed script, same harness: absent+warning → binding deleted (self-heal restored); list warnings → clean run, zero phantoms; unset limit → exit 1, zero deletes; `abc` → `ERROR: ORPHAN_LIMIT must be a whole number…`, exit 1; 30 orphans vs limit 25 → still refuses; Forbidden probe → still aborts naming the verb; dry-run and healthy-baseline behaviour unchanged. `helm lint` on the patched chart: 0 failed; ConfigMap round-trip byte-identical.
> What I checked and found CLEAN (so this list is closed, not open): the `IFS` dance is inert-but-harmless (a `for` word-list expands once — measured, 3 iterations regardless of mid-loop `IFS` resets); the `while read` subshells hold no counters (display/delete only; `KEPT`/`DANGLING` accumulate in-shell — measured `KEPT=4` across kinds); a failed `oc delete` ABORTS via `set -e`+`pipefail` before the `swept N` summary rather than being swallowed (measured, exit 1 after the first Forbidden delete); `grep -qxF` cannot false-match on empty `$EXISTING`; label values and object names cannot contain `|` or glob characters.

---

> **Fable:** S2 — REFUTED (it is unbounded, and that is correct)
> **Where:** `14-orphan-sweeper-script.yaml:171-201` (second sweep) vs `ORPHAN_LIMIT` at lines 110-122.
> **Trigger:** 30 RoleBindings whose roleRef Roles are all absent, `ORPHAN_LIMIT=5` — a mass roleName change across a policy matching many namespaces.
> **Consequence claimed by the worry:** an uncapped mass deletion. What actually happens: all 30 are deleted — and that is the *desired* outcome, because each deletion is individually gated on a definite per-object NotFound (rc=0 + empty with `--ignore-not-found`), and a binding whose Role is gone **grants nothing** (the script's own measured comment, line 147-148: "which grants nothing and reports nothing"). There is no access to lose; the operator rebuilds each binding with the correct roleRef. A cap here would *strand a partial self-heal* mid-policy and fail the sync while leaving some namespaces broken. The systemic failure modes that make the first sweep's cap necessary (a wrong CR list) cannot produce mass rc=0-empty probes: Forbidden, network and API errors all abort (measured: the Forbidden path exits 1 naming the missing verb, deleting nothing).
> **Fix:** none — no replacement block; the asymmetry between the two sweeps is correct because the first sweep's decision input is one global list (one wrong answer poisons every object), while the second sweep's is one probe per object.
> **Proof:** harness scenario 7: 30 dangling vs `ORPHAN_LIMIT=5` → 30 deleted, exit 0; scenario 8: Forbidden probe → exit 1, zero deletes. Live three-way table reproduced on CRC: exists → rc=0 + `role.rbac.authorization.k8s.io/spark-job-submitter-role`; absent → rc=0 empty; `--as=system:serviceaccount:default:nobody` → rc=1 Forbidden.

---

> **Fable:** S3 — REFUTED (fine at this scale; the prefetch is not worth it and carries a trap)
> **Where:** `14-orphan-sweeper-script.yaml:183` — one `oc get role` per kind=Role binding.
> **Trigger:** today, 3 such bindings (measured on CRC: `oud-poc-{crossfamily,platform,trino}`, all → `spark-job-submitter-role`); each probe measured at ~0.12s wall.
> **Where it stops being fine:** the Job's `activeDeadlineSeconds: 300` is the binding constraint. At ~0.12–0.3s per probe the budget breaks around ~1,000–2,000 kind=Role bindings; discomfort (multi-minute PostSync) starts around ~500. Today's count is 3 and every binding this chart's policies create adds one per namespace-with-the-label, so three orders of magnitude of headroom.
> **Why the "simple" fix is not worth it now:** `oc get role -A` up front must be **unfiltered** — a `-l managed-by` filter would miss hand-made Roles that legitimately satisfy a roleRef, read them as absent, and delete healthy bindings: the 0.19.1 defect shape reintroduced by an optimisation. Unfiltered, it returns every Role in every namespace (thousands on a real cluster) to answer a question about ~3, and replaces a per-object definite answer with membership in a snapshot taken before the deletes began. Revisit only if the binding count approaches the hundreds.
> **Fix:** none — no replacement block.
> **Proof:** `oc get rolebinding -A -l app.kubernetes.io/managed-by=… -o jsonpath="{range .items[?(@.roleRef.kind=='Role')]}…"` → 3 rows; `time oc get role spark-job-submitter-role -n oud-poc-crossfamily --ignore-not-found -o name` → 0.121s (absent-name probe: 0.125s).

---

> **Fable:** S4 — CONFIRMED (`get` is exercised on `roles` only; it is granted-but-unused on rolebindings, clusterrolebindings, namespaceconfigs and groupconfigs)
> **Where:** `15-orphan-sweeper-rbac.yaml:42-60` (the `rules:` block).
> **Trigger:** read the script's call inventory: the only by-name fetch anywhere is `oc get role <name> -n <ns>`; bindings are only ever *listed* (`-l` selector → list verb) and *deleted by name* (delete verb — no get involved: the 0.19.1 incident itself is the measured proof, since the buggy sweep **deleted bindings on every sync while `can-i get roles` answered no**). The CR kinds are only listed.
> **Consequence:** an auditor reading the ClusterRole believes the sweeper fetches individual bindings and CRs by name; it never does. The security delta of the surplus is ≈ nil (`delete` on the same resources is already granted, and constraint 7 accepts the breadth), so REJECT is defensible — but the rule as written also hosts the comment "`get` IS REQUIRED AND WAS THE BUG" over two resources where get is *not* required, which misstates the lesson the comment exists to teach.
> **Fix (complete, ready to apply):** replace the `rules:` block of the ClusterRole:
> ```yaml
> rules:
>   # The objects being swept. list to find them, delete to remove them. No create, no update — the
>   # sweeper never makes or edits a grant, which is what keeps it auditable. No `get` either: nothing
>   # fetches a binding by name, and the 0.19.1 incident is the measured proof delete works without it
>   # (the buggy sweep deleted bindings on every sync while `can-i get roles` still answered no).
>   - apiGroups: ["rbac.authorization.k8s.io"]
>     resources: ["rolebindings", "clusterrolebindings"]
>     verbs: ["list", "delete"]
>   # `get` IS REQUIRED HERE AND WAS THE BUG. The dangling-Role sweep asks "does this roleRef target
>   # exist?" with `oc get role <name> -n <ns>`, which needs get on the named resource — list is not
>   # enough. Without it the API returned Forbidden, the script read that as "the Role is gone", and it
>   # deleted three healthy RoleBindings on a no-op upgrade. Measured: deleted 06:10:36-40, rebuilt
>   # 06:10:37-42, so counts matched afterwards and the churn was invisible in `oc get`. The script now
>   # separates absent from forbidden and refuses to delete on any error, but this verb is what makes
>   # the question answerable in the first place — and it is the reason roles have their own rule.
>   - apiGroups: ["rbac.authorization.k8s.io"]
>     resources: ["roles"]
>     verbs: ["get", "list", "delete"]
>   # Read-only, and it is the whole basis of the decision: an object is an orphan only because the CR
>   # named in its provenance label is absent from this list.
>   - apiGroups: ["redhatcop.redhat.io"]
>     resources: ["namespaceconfigs", "groupconfigs"]
>     verbs: ["list"]
> ```
> **Proof:** call inventory grep of the script (only `oc get role "$drole"` is a named get); impersonated can-i matrix on CRC (all listed verbs currently yes for `system:serviceaccount:namespace-configuration-operator:namespace-configuration-operator-orphan-sweeper`); patched chart with this block: `helm lint` 0 failed, rendered rules = `[rolebindings, clusterrolebindings]/[list, delete]`, `[roles]/[get, list, delete]`, `[namespaceconfigs, groupconfigs]/[list]`; delete-without-get proven by the 0.19.1 commit's own measured timeline (deletes succeeded 06:10:36-40 while get was Forbidden).

---

> **Fable:** S5 — CONFIRMED (both sweeps delete nothing under `DRY_RUN=true` and still report what they would do)
> **Where:** `14-orphan-sweeper-script.yaml:130-131` (first sweep) and `186` (second sweep).
> **Trigger:** `DRY_RUN=true` with one orphan (owner CR gone) AND one dangling binding (Role gone) in the same run.
> **Consequence:** none adverse — measured zero `oc delete` invocations, exit 0, both objects reported. One wording blemish: the second sweep logs `…; deleting so the operator rebuilds it` per binding even in dry run (the summary line then says "left in place"). A reader of just that log line believes a delete happened that did not.
> **Fix:** the corrected wording (`would delete` under dry run) is already inside S1's replacement block — the two changes touch the same lines, so they ship together rather than as competing edits. No separate block.
> **Proof:** harness scenario 2 (current script): `DRY RUN: nothing will be deleted` … `rolebinding ns3/orphan-rb -> missing CR 'deleted-cr'` … `DRY RUN: leaving all 1 in place` … `rolebinding ns4/dangling-rb -> Role/gone-role does not exist; deleting so the operator rebuilds it` … `found 1 rolebinding(s) pointing at a missing Role (dry run: left in place)`; deletes log EMPTY; exit 0. Control (same fixture, `DRY_RUN=false`): both deleted. Fixed script, same fixture: identical except `would delete`.

---

> **Fable:** P1 — REFUTED
> **Where:** all four policy templates, checked in the render (`helm template … -f crc-values.yaml`).
> **What I checked:** (1) zero `\"` sequences anywhere in the render (`grep -c '\\"'` → 0), so no `| quote` ever touched a built string; (2) the surviving `{{ }}` population is exactly the intended operator set — 17× `{{ .Name }}`, 12× `{{ index .Labels "company.net/mnemonic" }}`, 3× `…app-environment…`, 3× `…oud-group…`, 4 `hasSuffix` guards + 4 `{{- end }}` — plus one `{{- with }}` which is a deliberate `` {{`…`}} `` escape inside a *comment* in the out-of-scope `02-subscription.yaml` (it renders as prose warning against that very trap); (3) zero unrendered Helm constructs (`.Values`/`.Release`/`.Chart`/`quote` absent from the render); (4) every `| quote` in the template sources sits on Helm-side scalars (`$p.description`, `$c.description`), never on a built string; (5) the Helm actions inside `#` comments (e.g. `{{ $r.name }}` in the per-template banners, `{{ $p.roleName }}` in 12's label comment) all reference defined Helm-side variables, so evaluation is intended and harmless.
> **Fix:** none — no replacement block.
> **Proof:** commands and counts above, run against the crc-values render; objectTemplate first-lines parsed from the rendered CRs show the guards intact (`{{- if hasSuffix "-cluster-admin" .Name }}` etc.).

---

> **Fable:** P2 — CONFIRMED, with the precise answer: **none of the three as posed — the asked-about state cannot match; the reachable neighbour state is a rejected object**
> **Where:** `12-custom-oud-group-namespaceconfig-rbac.yaml:117` (selector `labelKey Exists`) and `167/193` (name `"{{ $group }}-rb"`, subject `"{{ $group }}"`).
> **Trigger:** a namespace that *lacks* the label cannot be a "matching namespace" — `operator: Exists` requires the key, so the operator never renders for it (no object, no error: a true nothing, not a silent no-op). The reachable bad state is the label present with an **empty value** (`company.net/oud-group: ""`), which `Exists` matches. Then: the Role template renders and applies normally (it does not use the value); the RoleBinding renders `name: "-rb"` with `subjects[0].name: ""` — and `-rb` fails DNS-1123 validation (leading hyphen), so the API **rejects the object**. Per the operator behaviour this chart has already measured (the "cannot change roleRef" case, template header), the operator error-loops on the failed create while the CR logs "resources processed successfully". The Kyverno allowlist (`kyverno-namespace-oud-group.yaml`) would flag the value but runs `validationFailureAction: Audit` — it does not block.
> **Consequence:** a reader of `oc get namespaceconfig bdp-oud-group-rbac` and of the namespace sees a healthy CR, a present label and a created Role, and believes the group is bound; no RoleBinding exists and nothing on the cluster says why.
> **Fix (complete, ready to apply):** document the trap at the point of use — replace the RoleBinding banner comment in 12 (no logic change; an operator-side guard string would convert a visible error-loop into a silent no-op, which is worse, and value validation is Kyverno's job by this chart's own design):
> ```yaml
>     # -------------------------------------------------------------------------
>     # RoleBinding — subject is the label value, used VERBATIM
>     #
>     # AN EMPTY LABEL VALUE IS A REACHABLE BAD STATE: `labelKey Exists` matches a namespace whose
>     # value is "", the Role above still renders, and this binding renders name "-rb" with subject ""
>     # — which the API REJECTS (DNS-1123), so the operator error-loops on the create while the CR
>     # logs "resources processed successfully": no grant, no visible error. The Kyverno allowlist
>     # audits the value but does not block (Audit mode). If this policy's grant is missing in one
>     # namespace, check the label VALUE before reading the operator log.
>     # -------------------------------------------------------------------------
> ```
> **Proof:** rendered selector is exactly `[{key: company.net/oud-group, operator: Exists}]`; live label values on CRC all non-empty (3 namespaces checked); apimachinery's IsDNS1123Subdomain regex rejects `-rb` and accepts `bda-rbac-trino-alpha-users-rb` (run in the proof script); Kyverno policy line 50: `validationFailureAction: Audit`. The error-loop-while-CR-reports-success behaviour is the operator's measured response to a refused object per this repo's own 0.17.0 record; not re-reproduced here because it needs cluster writes.

---

> **Fable:** P3 — CONFIRMED, and the claim's parenthetical is only half-true: **Roles coexist only while roleNames differ**
> **Where:** `12-custom-oud-group-namespaceconfig-rbac.yaml:51-65` (the convention comment) and `129/198` (Role name, roleRef = `$p.roleName`).
> **Trigger:** two enabled `oudGroup.policies` sharing values — measured render: a `bdp`+`xyz` overlay sharing BOTH `labelKey: company.net/oud-group` AND `roleName: spark-job-submitter-role` renders two CRs with **identical selectors**, both creating Role `spark-job-submitter-role` and both naming the RoleBinding `{{ index .Labels "company.net/oud-group" }}-rb`, with no refusal from Helm (correct — 0.17.0 established no render guard can be right, since collision is a cluster fact).
> **What actually collides:**
> - **Shared `labelKey`** (roleNames distinct): only the RoleBinding is contested. Both Roles coexist; the second policy creates ZERO bindings — `cannot change roleRef` error-loop while the CR logs success. Already documented and measured in this file's own comment (the 0.17.0 record); nothing new.
> - **Shared `roleName`** (selectors overlapping on ≥1 namespace — including the different-labelKeys-same-namespace case): the **Role object itself** is contested, and this one is undocumented and worse. Role `rules` are SPEC, and spec propagates (`excludedPaths` covers only `.metadata`/`.status` — labels-and-annotations.md §6, measured), so the two CRs rewrite each other's `rules` on every reconcile: the namespace's effective permissions oscillate between the two lists, nothing errors, and both CRs log success. The RoleBindings collide too only if the label *values* also coincide.
> **Consequence:** a reader of `oc get role spark-job-submitter-role -o yaml` believes the rules they see are the policy's steady state; they are one phase of a permanent two-CR rewrite war, and `oc auth can-i` answers change between reconciles with no event explaining why.
> **Fix (complete, ready to apply):** extend the convention comment in 12 — replace the whole `{{- /* ONE labelKey PER POLICY … */ -}}` block with:
> ```yaml
> {{- /*
>   ONE labelKey PER POLICY — a convention, not a render-time guard, because it cannot be one. The
>   RoleBinding is named "<label value>-rb", and that value is read from a namespace at reconcile time, so
>   Helm cannot know whether two policies would collide. Uniqueness is (namespace, name), which makes it a
>   fact about the cluster rather than about values.
>
>   IF TWO POLICIES DO SHARE A labelKey, the failure is silent — measured by trying it:
>     - both Roles are created and coexist; only the RoleBinding is contested
>     - the second policy creates ZERO RoleBindings, because roleRef is immutable:
>         RoleBinding "…-rb" is invalid: roleRef: Invalid value: …: cannot change roleRef
>     - the operator error-loops on that patch while the CR logs "resources processed successfully"
>
>   So the CR reads healthy and the grant is absent. If a grant here is missing, grep the manager log for
>   "cannot change roleRef" first.
>
>   ONE roleName PER POLICY TOO, for the same reason with a worse failure. "Each policy defines its own
>   Role" holds only while the names differ: two policies sharing a roleName whose selectors overlap on a
>   namespace are two CRs reconciling ONE Role object — and rules are SPEC, which propagates, so each
>   reconcile rewrites the other's rules and the namespace's effective permissions oscillate between the
>   two lists. Nothing errors and both CRs log success. Unguardable at render time for the same reason as
>   labelKey: whether the selectors overlap is a fact about the cluster, not about values.
> */ -}}
> ```
> **Proof:** overlay render (`helm template … -f crc-values.yaml -f p3-values.yaml`): `rendered without any refusal: 2 oud-group CRs`, identical `Exists` selectors, both Role name-lines `name: spark-job-submitter-role`, both binding name-lines `name: "{{ index .Labels "company.net/oud-group" }}-rb"`. Spec-propagation grounding: labels-and-annotations.md §6 ("Spec-level changes — subjects, roleRef, rules — do propagate", measured in-repo). The live rewrite war itself was not reproduced — it needs cluster writes, which this review is barred from.

---

> **Fable:** K1 — CONFIRMED: hook-weight DIRECTION is unchecked, so a sweeper weighted below the approver passes every assertion and breaks a plain-Helm install
> **Where:** `working-sessions/scripts/check-ordering.py:224-227` — the only hook-weight rule is uniqueness.
> **Trigger:** set the sweeper Job's `helm.sh/hook-weight` from `"20"` to `"4"` (unique, so the shared-weight check is happy; waves untouched, so every wave assertion is happy). Under plain Helm — the exact install command crc-values.yaml documents — post-install hooks run in ascending weight order: the sweeper (4) now runs before the InstallPlan approver (5), i.e. before the operator's CSV can install, so `oc get namespaceconfig` fails against a cluster with no such CRD, the Job fails, and `helm install` fails with it. The chart's own comment (16-orphan-sweeper-job.yaml line 5) states this ordering is load-bearing; nothing asserts it.
> **Consequence:** CI reports `OK: every template document declares a wave, … and no two hooks share a weight` for a chart whose plain-Helm install cannot succeed — a reader believes the ordering is verified when only its uniqueness is.
> **Fix (complete, ready to apply):** in `check()`, record which hook is the sweeper and its hook events, then assert it is the last hook of its event. Two replacements inside `check()` (the rest of the function is unchanged):
> ```python
>         # Helm orders hooks by weight, then falls back to NAME. Two hooks sharing a weight are
>         # therefore ordered by accident, and this chart's hooks depend on each other in sequence.
>         if HOOK in ann:
>             if raw_weight is None:
>                 errors.append("%s: %s/%s is a Helm hook with no %s" % (label, kind, name, WEIGHT))
>             else:
>                 hook_weights.setdefault(int(raw_weight), []).append(
>                     ("%s/%s" % (kind, name), labels(doc).get(COMPONENT) == SWEEPER, ann[HOOK]))
> ```
> ```python
>     for weight, holders in sorted(hook_weights.items()):
>         if len(holders) > 1:
>             errors.append("%s: hooks share %s=%d, so Helm falls back to name order and their "
>                           "sequence is accidental: %s" % (label, WEIGHT, weight,
>                                                           ", ".join(h for h, _, _ in holders)))
>
>     # Uniqueness above cannot see DIRECTION. Under plain Helm the hooks run in weight order, and the
>     # sweep inspects the state every other hook produces — the operator install included — so it must
>     # be the LAST hook of its event. Weighted below the InstallPlan approver it would run before the
>     # policy CRDs exist: `oc get namespaceconfig` fails, the Job fails, and the install fails with it.
>     # Only hooks sharing one of the sweeper's events are compared; a pre-install hook is a different
>     # queue and its weight is not on this axis.
>     sweeper_hooks = [(w, ev) for w, holders in hook_weights.items() for _, s, ev in holders if s]
>     for sweep_w, sweep_ev in sweeper_hooks:
>         sweep_events = set(sweep_ev.replace(" ", "").split(","))
>         for weight, holders in sorted(hook_weights.items()):
>             for holder, is_sweeper, ev in holders:
>                 if is_sweeper or not (set(ev.replace(" ", "").split(",")) & sweep_events):
>                     continue
>                 if weight >= sweep_w:
>                     errors.append("%s: hook %s has %s=%d, at or above the sweeper's (%d). The sweep "
>                                   "must run after every hook that installs or configures the operator, "
>                                   "or it inspects a cluster where the policy CRDs do not exist yet."
>                                   % (label, holder, WEIGHT, weight, sweep_w))
> ```
> **Proof:** mutated chart copy (weight 20→4): current script → `OK: …` (passes). Patched script → real chart passes; mutated chart fails with `hook Job/namespace-configuration-operator-installplan-approver has helm.sh/hook-weight=5, at or above the sweeper's (4)…` (and the same for image-override at 10), exit 1.

---

> **Fable:** K2 — CONFIRMED: the wave check is a SUBSTRING test, so the key's appearance in a comment satisfies it — and for a gated template no render exists to catch the miss
> **Where:** `working-sessions/scripts/check-ordering.py:94` — `if WAVE not in chunk:`.
> **Trigger:** in `00-namespace.yaml` (gated behind `createNamespace: false` in values.yaml AND the crc overlay — the very template the source check exists for) comment the annotation out during debugging: `# TODO restore: argocd.argoproj.io/sync-wave: "-2"`. The substring is still present, the source check passes, and no values combination renders the file, so the render check never sees it. Full run: `OK: every template document declares a wave, …`.
> **Consequence:** the check's own success line asserts "every template document declares a wave" about a document that declares none — the exact vacuous-pass failure mode the script's RULE 3 comment promises it will never have.
> **Fix (complete, ready to apply):** replace the wave test inside `check_template_sources` (rest of the function unchanged):
> ```python
>             docs_seen += 1
>             # An annotation LINE, not a substring. `WAVE in chunk` was satisfied by the key merely
>             # appearing in a comment — so commenting the annotation out passed this check, and for a
>             # gated template no render exists to catch it. Anchored to line start plus indentation,
>             # which a `#` before the key cannot match.
>             if not re.search(r"(?m)^\s*%s\s*:" % re.escape(WAVE), chunk):
>                 kind = re.search(r"(?m)^kind:\s*(\S+)", chunk).group(1)
>                 errors.append("%s (document %d, kind %s) declares no %s. ArgoCD would read it as "
>                               "wave 0 — the Subscription's wave — so it could be deleted after the "
>                               "operator it depends on."
>                               % (os.path.relpath(path, REPO), i + 1, kind, WAVE))
> ```
> **Proof:** mutated chart copy (annotation commented out in 00-namespace.yaml): current script → `OK` (passes). Patched script → real chart passes (every live wave is a genuine annotation line); mutated chart fails: `templates/00-namespace.yaml (document 1, kind Namespace) declares no argocd.argoproj.io/sync-wave…`, exit 1. Also checked and could NOT break the `^---\s*$` splitter itself: a `---` inside the sweeper's block scalar is always indented (block scalars cannot reach column 0), the per-`kind:` count anchors at column 0 so nested `kind:` lines inside objectTemplates are not miscounted, and a range emitting N documents from one `---` still shares one source wave line — so the split's only measured failure is the substring test above.

---

> **Fable:** D1 — CONFIRMED; four blocks restate a fact stated elsewhere. Every WHY, measured number and trap survives in the replacements.
> **Where / Fix / savings, in priority order:**
>
> **D1-a — `12-custom-oud-group-namespaceconfig-rbac.yaml:146-154`** (the Role's annotation comment). Nine lines making the label-vs-annotation point that the SAME file makes in three lines on the RoleBinding (185-187), and which labels-and-annotations.md §2 owns canonically. Replace with the file's own short form (saves 5 lines):
> ```yaml
>           annotations:
>             # The CR that created this object, readable. Same value as the config-source LABEL above:
>             # the label is what you select on, this is what you read in `oc get -o yaml` / `oc describe`
>             # — which is also why the old `oc -l`-on-an-annotation trap is now harmless.
>             rbac.ocp.io/source-namespaceconfig: {{ $name }}
> ```
> (The identical nine-line block in `10-baseline-namespaceconfig-rbac.yaml:170-179` is that file's only full statement; same condensation applies if wanted, same wording, saves another 5. Optional.)
>
> **D1-b — `values.yaml:356-358`**: two consecutive intro sentences for `roleName` saying the same thing ("The Role the RoleBinding points at…" / "The Role this policy creates, and what its RoleBinding points at."). Replace both with one (saves 1 line):
> ```yaml
>         # The Role this policy creates — one per namespace, from the first template — and what its
>         # RoleBinding points at.
> ```
>
> **D1-c — `values.yaml:335-343`** (the `name: ''` comment): the rename-is-delete-plus-create mechanism is stated twice in one block. Replace the whole comment (saves 1 line, keeps ~4s/~50s and the earlier-version correction, and fixes the stale `abc` example — the shipped key is `bdp`):
> ```yaml
>         # EMPTY = derive from the map key above: `bdp` -> bdp-oud-group-rbac. Set it explicitly only
>         # to pin a name a cluster already has.
>         #
>         # CHANGING EITHER — the key or this name — IS A REVOCATION, not an orphaning. Helm treats a
>         # renamed resource as delete-plus-create: the old CR's namespaceconfig-controller finalizer
>         # revokes every object it made and the new CR rebuilds them under the new name. Measured on
>         # this cluster: 6 objects (3 Roles + 3 RoleBindings) gone in ~4s, back within ~50s. Nothing is
>         # left behind — an earlier version of this comment claimed objects would be orphaned, which is
>         # the opposite of what happens and would have led someone to hunt for stale objects instead of
>         # planning a window.
>         name: ''
> ```
>
> **D1-d (optional, lowest priority)** — the "TWO TEMPLATE ENGINES" + "`#` is not a Helm comment" block appears in all four policy files (10:40-51, 11:34-45, 12:26-37, 13:49-60), ~12 lines each. 0.19.0 deliberately kept one copy per file as an at-point-of-use trap warning, so this is a judgment call, not an error. If condensing: 8 lines per file preserving all three traps and the pointer (saves ~16 lines total; swap "namespace…its labels" for "GROUP name, not a namespace" in 11/13):
> ```yaml
> # ── TWO TEMPLATE ENGINES, SAME { } DELIMITERS ──────────────────────────────
> # Helm renders this file at install; the OPERATOR renders each objectTemplate later, once per matching
> # namespace, where .Name is the namespace and .Labels are its labels. Operator expressions are BUILT AS
> # STRINGS below so Helm cannot evaluate them — if it does, it tests an undefined .Name, renders the
> # object away, and reports success: no error, only a missing grant. Two traps guard that line: a `#`
> # comment is YAML, not Helm — an action inside one IS evaluated; and never `| quote` a built string —
> # the operator renders Go-template FIRST and parses YAML SECOND, so a backslash-quote breaks the parse.
> # Full explanation, including how $group is derived three ways: working-sessions/docs/templating-guide.md
> ```
> **Proof:** duplication located by grep across the four templates and values.yaml; the condensed forms carry every measured number (4s/50s), every trap (evaluate-away, `#`-is-YAML, no-`| quote`), and the doc pointer.

---

> **Fable:** D2 — CONFIRMED, six instances; the two the task flagged as highest-value are D2-1 (comments assert a safety default the chart no longer ships) and D2-2/D2-6 (remediation selectors that match zero objects). Every claim below is measured.
>
> **D2-1 — values.yaml claims the policies are off by default; they are on, and a plain install creates RBAC.**
> **Where:** `values.yaml:285-286` ("OFF BY DEFAULT — all of it… Turn on the parent flag"), `458-460` (baseline "OFF is CHART SAFETY… Turn it on deliberately"), `530-533` ("The two switches above it — namespaceConfigPolicy.enabled and baseline.enabled — are both false, so a plain `helm install` still creates nothing"), `566-567` (clusterRbac "OFF is CHART SAFETY").
> **Trigger:** commit `9bd965e` (0.18.0) flipped all four flags to `true` — deliberately, with CI updated to "defaults render what values declares" — and left these comments behind.
> **Consequence:** an operator reading values.yaml before installing on a new cluster believes stock defaults grant nothing; `helm template` with defaults renders **3 policy CRs** (`baseline-nonprod-rbac`, `baseline-prod-rbac`, `baseline-cluster-rbac`), so a plain install immediately grants the baseline across every matching namespace and synced group.
> **Fix (complete, ready to apply):** four comment replacements —
> `values.yaml:284-286` →
> ```yaml
> #
> # ON BY DEFAULT since 0.18.0 — a deliberate flip, with CI now asserting "defaults render what values
> # declares" instead of "defaults render nothing". A plain `helm install` with stock values therefore
> # CREATES RBAC: the two baseline NamespaceConfigs and the cluster GroupConfig render immediately
> # (bdp and customGroupConfig still ship off). Set this false — and clusterRbac.enabled below — before
> # installing anywhere that must not receive the baseline.
> ```
> `values.yaml:458-460` (keep the revocation warning that follows — it is correct) →
> ```yaml
>     # ON BY DEFAULT since 0.18.0, with the parent switch: the baseline is what this chart is for.
>     # Turning it OFF on a cluster that has it is a REVOCATION, not a no-op — see below.
>     #
> ```
> `values.yaml:530-533` →
> ```yaml
>       # PROD RBAC THEREFORE SHIPS BY DEFAULT: the two switches above it — namespaceConfigPolicy.enabled
>       # and baseline.enabled — are both true since 0.18.0, so a plain `helm install` creates the prod CR
>       # too. This flag decides what the baseline CONTAINS, and the answer is: the full baseline. Turn it
>       # off only to deploy the nonprod half alone.
> ```
> `values.yaml:566-567` →
> ```yaml
>   # ON BY DEFAULT since 0.18.0, like the namespace baseline. Turning it OFF on a cluster that has it
>   # is a REVOCATION, not a no-op:
> ```
> **Proof:** `helm template t charts/namespace-configuration-operator` (no -f) → `GroupConfig baseline-cluster-rbac`, `NamespaceConfig baseline-nonprod-rbac`, `NamespaceConfig baseline-prod-rbac` (22 docs total). `git log -L` pins the flip to `9bd965e` ("feat(chart): policies enabled by default…", values diff `enabled: false -> true`).
>
> **D2-2 — the sweeper's values.yaml and RBAC-file comments still describe the pre-0.16.0 annotation mechanism; the script reads the config-source LABEL.**
> **Where:** `values.yaml:126-129` ("names a policy CR in rbac.ocp.io/source-{namespace,group}config… Objects without that annotation are counted and left alone") and `15-orphan-sweeper-rbac.yaml:14-19` (same wording, plus the limit claim handled in D2-3).
> **Trigger:** 0.16.0 unified provenance onto the `rbac.ocp.io/config-source` label; the script's own comment (14, lines 79-84) says so explicitly. These two summaries were not updated.
> **Consequence:** someone debugging "why was/wasn't this object swept" inspects the annotations; an object stripped of its annotation but carrying the label WOULD be swept, and vice versa — the doc sends them to the wrong key on a delete decision.
> **Fix (complete, ready to apply):** `15-orphan-sweeper-rbac.yaml:14-19` →
> ```yaml
> # WHAT NARROWS IT IN PRACTICE — the permission is broad, the script is not. It only ever deletes an
> # object that satisfies BOTH conditions together: carries
> # app.kubernetes.io/managed-by=namespace-configuration-operator, AND names a policy CR in its
> # rbac.ocp.io/config-source LABEL that does not exist (the label, not the source-*config annotation —
> # one provenance key since 0.16.0, the same one a human selects on). Objects without that label are
> # counted and left alone. A failed CR lookup ABORTS the run outright; orphanSweeper.limit is the
> # backstop for a CR list that is legitimately empty or wrong for the objects on the cluster, so a bad
> # upgrade cannot cascade into deleting everything the chart grants.
> ```
> `values.yaml:124-129` (the tail of the orphanSweeper header) →
> ```yaml
> # IT HOLDS A BROAD PERMISSION. The sweeper runs with a ClusterRole granting delete on rolebindings,
> # clusterrolebindings and roles cluster-wide, because RoleBindings live in every namespace and
> # ClusterRoleBindings are cluster-scoped. What narrows it is the script, not the RBAC: an object is only
> # ever deleted if it carries app.kubernetes.io/managed-by=namespace-configuration-operator AND names a
> # policy CR in its rbac.ocp.io/config-source LABEL that does not exist. Objects without that label are
> # counted and left alone.
> ```
> **Proof:** script line 85-86 reads `{.metadata.labels.rbac\.ocp\.io/config-source}`; script comment 79-81: "READS THE config-source LABEL, not the old source-{namespace,group}config annotations."
>
> **D2-3 — the ORPHAN_LIMIT comments still name "a failed API lookup" as what the cap guards; since 0.19.1 a failed lookup aborts before the cap is consulted.**
> **Where:** `values.yaml:143-146` ("…is also what a FAILED API lookup looks like — and in that case every object this chart manages appears orphaned") and `14-orphan-sweeper-script.yaml:60-63` ("Guard against sweeping the whole cluster if the CR lookup failed rather than genuinely returned nothing… far more likely to be a broken API call"). (`15:18-19` covered by D2-2's block.)
> **Trigger:** 0.19.1 made every lookup abort on rc≠0 — the script's own lines 49-52 say "Abort instead". A failed lookup can no longer reach the cap.
> **Consequence:** a reader weighing whether the cap is still needed concludes its threat model is already handled by the aborts and removes or raises it — losing the guard for the rc=0 catastrophes that remain real and measured (every policy switched off by a bad `-f` upgrade; the 0.16.0 label-value migration where the cap stopped a 36-object revocation, labels-and-annotations.md §2).
> **Fix (complete, ready to apply):** `values.yaml:141-147` →
> ```yaml
>   # Abort a run that would delete more than this many objects in one go. 0 disables the cap.
>   #
>   # THIS IS A BLAST-RADIUS GUARD, not a tuning knob. Since 0.19.1 a FAILED lookup aborts before this
>   # cap is consulted; what the cap still guards is the rc=0 catastrophe — every policy switched off by
>   # a bad -f upgrade, or a label-value migration whose existing objects match no CR (measured at
>   # 0.16.0: 36 stale objects, and this cap turned the mass revocation into a failed sync). 25 is above
>   # the largest legitimate sweep seen here (20) and well below the full object count (42), so such a
>   # state aborts loudly instead of revoking the cluster.
>   limit: 25
> ```
> The script-side comment (14:60-63) is already rewritten inside S1's replacement block ("The cap below guards against a run whose CR list is legitimately EMPTY or legitimately WRONG…"); if S1 is rejected, that paragraph should still be applied on its own.
> **Proof:** script lines 53-56 (`|| fail` on both CR lookups) vs line 64 (the cap) — the abort precedes the cap; harness scenario F13 shows the cap firing on a legitimately-empty CR list (30 candidates vs limit 25 → refusal).
>
> **D2-4 — file 12 documents a `configSource` values key that does not exist, and claims "setting either explicitly overrides the derivation".**
> **Where:** `12-custom-oud-group-namespaceconfig-rbac.yaml:66-71` ("NAME AND configSource ARE DERIVED FROM THE MAP KEY… values.yaml ships both as ''… Setting either explicitly overrides the derivation").
> **Trigger:** values.yaml ships only `name: ''`; there is no `configSource` key anywhere in the chart, and the `rbac.ocp.io/config-source` label is unconditionally `{{ $name }}` (12:139,173).
> **Consequence:** someone needing to pin a config-source value (e.g. to keep selectors stable across a CR rename) reads that Helm can override it, adds `configSource:` to values, and gets a silent no-op — the label follows the CR name regardless. This is the "implies Helm can override a value it cannot" case.
> **Fix (complete, ready to apply):** replace the whole `{{- /* NAME AND configSource … */ -}}` comment block with:
> ```yaml
> {{- /*
>   NAME IS DERIVED FROM THE MAP KEY, so the key is the single place a policy's identity is written.
>   values.yaml ships name: '' and this fills it in: key `bdp` gives the CR name bdp-oud-group-rbac.
>   Setting name explicitly overrides the derivation — the escape hatch for a policy that must keep a
>   name it already has on a cluster. The rbac.ocp.io/config-source label always carries the CR name;
>   it is not separately settable, so name (or the key) is also the selector for this policy's objects.
>
>   THE CONSEQUENCE OF DERIVING, worth knowing before renaming a key: the CR name IS cluster identity,
>   and Helm treats a renamed resource as delete-plus-create — the old CR's finalizer revokes every
>   object it made and the new CR rebuilds them. Measured elsewhere in this chart at ~4s to revoke and
>   ~50s to restore. Rename deliberately, not while tidying.
> */ -}}
> ```
> **Proof:** `grep -rn configSource charts/` → no values key, no template read; `rbac.ocp.io/config-source: {{ $name }}` at 12:139 and 12:173.
>
> **D2-5 — values.yaml carries an orphaned comment block for that same removed knob.**
> **Where:** `values.yaml:351-354` ("The policy's short name, written to rbac.ocp.io/config-source on every object this policy creates… Keep it short and distinct from every other policy's.") — no key follows it; the next real key is `roleName`.
> **Trigger:** the short-name key was removed when config-source became the CR name (0.16.0); the comment survived, describing a knob a reader cannot find.
> **Consequence:** a reader hunting for where to set the config-source label concludes the key is merely missing from their file and invents one (silent no-op), instead of learning it derives from the CR name.
> **Fix (complete, ready to apply):** delete lines 351-355 (the block plus its trailing blank line) — the fact it tried to state now lives in D2-4's corrected block. Combined with D1-b this leaves the roleName stanza as:
> ```yaml
>         # The Role this policy creates — one per namespace, from the first template — and what its
>         # RoleBinding points at.
>         #
>         # CHANGING THIS IS SELF-HEALING on a plain `helm upgrade` — no manual step. It takes a detour
>         # worth knowing about, because roleRef is IMMUTABLE in Kubernetes:
>         #   1. the operator creates the new Role and removes the old one
>         #   2. it CANNOT repoint the existing RoleBinding, so that patch fails with "cannot change
>         #      roleRef" and the binding is left referencing a Role that is gone — granting nothing
>         #   3. the orphan sweeper deletes any RoleBinding whose Role does not exist, and the operator
>         #      rebuilds it from the CR with the correct roleRef
>         # Measured end to end: 3 bindings repointed within 15 seconds of the upgrade, grants intact.
>         # The sweep is scoped to roleRef kind=Role for a reason — see templates/14-orphan-sweeper-script.
>         roleName: spark-job-submitter-role
> ```
> (Checked the flagged case while here: no in-scope file still claims a roleName change needs a manual step — values.yaml:359-367 and labels-and-annotations.md §6 both already state it self-heals. Verified by grep for `manual`/`roleName` across the scope.)
> **Proof:** values.yaml 351-358 read in place — the block precedes `roleName` with no owning key; `grep -n configSource charts/namespace-configuration-operator/values.yaml` → nothing.
>
> **D2-6 — labels-and-annotations.md ("the label contract") and two remediation comments name label values that match ZERO live objects.**
> **Where:** labels doc line 5 ("Chart 0.8.0… 5 CRs and the 55 objects"), line 34 (`abc-oud-group-rbac`), line 36 (`ns-admin`, `submitter` as "values on the cluster today"), line 37 (`oud-group-submitter-role`), line 70 (`abc-oud-group-rbac`), line 205 (cookbook: `-l rbac.ocp.io/config-source=nonprod-rbac`); plus `values.yaml:517` (`config-source=nonprod-rbac,role-type=ns-admin` — the ns-admin cleanup verification), `values.yaml:623-624` (`config-source=cluster-rbac`), `10-baseline-namespaceconfig-rbac.yaml:143` (`config-source=nonprod-rbac`).
> **Trigger:** 0.16.0 renamed config-source values to CR names; 0.18.0 renamed `abc`→`bdp` and `submitter`→`spark-job-submitter` and removed the ns-admin tier. The doc's own §2 records the 0.16.0 rename — and its §5 cookbook still uses the retired value.
> **Consequence:** every one of these is a copy-paste command that reports success while matching nothing — the exact failure the doc's §2 closes with ("Four documented remediation commands in this repo once got that wrong and reported success while matching zero objects"). Measured today: `config-source=nonprod-rbac` → 0 objects, `=baseline-nonprod-rbac` → 20; `config-source=cluster-rbac` → 0, `=baseline-cluster-rbac` → 12. A cleanup "verify the count reaches zero" step passes vacuously.
> **Fix (complete, ready to apply):**
> - labels doc line 5: `cluster — 5 CRs and the 55 objects they created` → re-measure and restate: `Chart 0.19.1. Every value below was re-verified against the running cluster — 5 CRs and the 42 objects they created` (42 = 26 RoleBindings + 13 ClusterRoleBindings + 3 Roles, measured).
> - line 34 value list: `` `baseline-nonprod-rbac` `baseline-prod-rbac` `baseline-cluster-rbac` `custom-cluster-rbac` `bdp-oud-group-rbac` ``
> - line 36 value list: `` `ns-developer` `ns-audit` `cluster-admin` `cluster-developer` `cluster-audit` `database-admin` `spark-job-submitter` `` (ns-admin removed with its tier — 0 live objects carry it)
> - line 37 value list: `` `admin` `edit` `view` `database-admin` `spark-job-submitter-role` ``
> - line 70: `` `baseline-nonprod-rbac` `baseline-prod-rbac` `bdp-oud-group-rbac` ``
> - line 205: `oc get rolebinding -A -l rbac.ocp.io/config-source=baseline-nonprod-rbac`
> - `values.yaml:517`: `oc delete rolebinding -A -l rbac.ocp.io/config-source=baseline-nonprod-rbac,rbac.ocp.io/role-type=ns-admin`
> - `values.yaml:623-624`: `oc delete clusterrolebinding -l rbac.ocp.io/config-source=baseline-cluster-rbac,rbac.ocp.io/role-type=cluster-admin` (and the matching `oc get`)
> - `10-baseline-namespaceconfig-rbac.yaml:143`: `oc delete rolebinding -A -l rbac.ocp.io/config-source=baseline-nonprod-rbac   # baseline-prod-rbac for the prod CR`
> **Proof:** live queries above (0 vs 20, 0 vs 12); live label-value inventory across all 42 managed objects: config-source ∈ {baseline-cluster-rbac, baseline-nonprod-rbac, baseline-prod-rbac, bdp-oud-group-rbac, custom-cluster-rbac}, role-type contains `spark-job-submitter` and no `ns-admin`/`submitter`, bound-role contains `spark-job-submitter-role` and no `oud-group-submitter-role`.

---

> **Fable:** N1 — CONFIRMED (out-of-scope file, flagged for a later pass): `crc-values.yaml:69-70` calls customGroupConfig "THE ONE GENUINE OVERRIDE… the only policy still defaulting to false in values.yaml". `bdp` also defaults to false in values.yaml and is switched on in the same file (crc-values.yaml:39-40) — two genuine overrides, not one. An upgrade that drops the bdp stanza revokes that policy exactly the way the comment warns about for customGroupConfig. One-line fix: "THE TWO GENUINE OVERRIDES are this and oudGroup.policies.bdp.enabled above — the only flags false in values.yaml…". Not fixed here: the file is outside this review's write scope.
> **Proof:** `values.yaml:327-328` (`bdp: enabled: false`) vs `crc-values.yaml:39-40` (`bdp: enabled: true`).

---

> **Fable:** N2 — CONFIRMED (out-of-scope file, flagged for a later pass): `templates/rbac-policies/_README.txt:12` still names the oud-group CR `abc-oud-group-rbac`; the shipped key has been `bdp` (→ `bdp-oud-group-rbac`) since 0.18.0, and that is what the live cluster runs. Same one-word fix as D2-6's value lists.
> **Proof:** grep hit at `_README.txt:12`; live CR list shows `bdp-oud-group-rbac`.

---

### Fable — verification ledger

| artefact | result |
|---|---|
| `helm lint` (chart as shipped, and with S1+S4 blocks applied) | 0 failed, both |
| `helm template` defaults / crc-values | 22 docs / renders; policy CR sets as stated above |
| `check-ordering.py` as shipped | OK on real chart; **OK on both broken mutations (K1, K2)** |
| `check-ordering.py` with K1+K2 fixes | OK on real chart; fails both mutations with the messages quoted |
| sweeper harness (stub oc), current script | scenarios 1-12: S1a, S1b, S5, S2, forbidden-abort, counter/IFS results as quoted |
| sweeper harness, S1 replacement script | all corrected behaviours + no regressions, quoted above |
| live CRC (read-only + `--as=`) | CR names, 42-object label inventory, can-i matrix, three-way probe table, probe timing, stale-selector 0-match proofs |
