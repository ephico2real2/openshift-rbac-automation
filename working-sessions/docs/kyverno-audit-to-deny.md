# Turning the Kyverno policies from Audit to Deny

Companion to `working-sessions/policies/kyverno-restrict-nco-writers.yaml` and the older ClusterPolicies in the same
directory. Everything below was measured on the sandbox (Kyverno 1.16.1, one admission-controller replica) on
2026-09-05. The policy headers hold the identity and match reasoning and the failure-mode measurements; this guide
holds the procedure. On `failurePolicy` the writers header states the source finding (the 1.16.1 compiler consults it
for matchConditions errors, and it governs the no-verdict path) and this guide adds what the CRD's own description
claims; the measured behaviour under "What Deny changes" is the same in both.

## The short answer

**No new YAML.** Each policy switches mode by changing one field in the file it already lives in, re-applying that
file, and running the verification that belongs to it. The companion ValidatingAdmissionPolicy is already enforcing.

| Policy (file) | Kind | Field to change | Today | Enforcing value |
|---|---|---|---|---|
| `kyverno-restrict-nco-writers.yaml` (`restrict-nco-config-writers`) | `policies.kyverno.io/v1beta1` ValidatingPolicy | `spec.validationActions` | `[Audit]` (Deny proven 2026-09-05, then reverted by decision) | `[Deny]` |
| `vap-protect-kyverno-configuration.yaml` (`protect-kyverno-configuration`) | `admissionregistration.k8s.io/v1` ValidatingAdmissionPolicy + Binding | `spec.validationActions` on the **Binding** | `[Deny]` | already `[Deny]` |
| `kyverno-group-naming-app-ocp-rbac.yaml` (`group-naming-app-ocp-rbac`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |
| `kyverno-group-naming-bda-rbac.yaml` (`group-naming-bda-rbac`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |
| `kyverno-namespace-oud-group.yaml` (`namespace-oud-group-allowlist`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |
| `kyverno-validation-only.yaml` (`rbac-standards-enforcement`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |

Two vocabularies, one meaning, and the CEL objects that carry the mode are not the same kind:

- `policies.kyverno.io/v1beta1` ValidatingPolicy: `spec.validationActions` is a list; Kyverno 1.16 accepts `Deny`,
  `Audit` and `Warn`. Enforcing is `[Deny]`. `Warn` adds a warning header and still admits the request.
- `admissionregistration.k8s.io/v1` ValidatingAdmissionPolicy**Binding**, not the ValidatingAdmissionPolicy: the
  Binding's `spec.validationActions` is the list (`Deny`, `Warn`, `Audit`); the Policy kind has no such field. The
  companion Binding is already `[Deny]`.
- `kyverno.io/v1` ClusterPolicy: the scalar `spec.validationFailureAction`, values `Audit` or `Enforce` (the live CRD's
  words). The top-level field is deprecated in favour of `validate.failureAction` per rule and still honoured on 1.16.1.

Writing `Deny` into a ClusterPolicy is rejected by the schema; writing `Enforce` into a ValidatingPolicy is too.

## What Deny changes, and what it does not

- **Audit** admits the request and records a PolicyViolation event (and a PolicyReport row for the ClusterPolicies).
  A policy in Audit protects nothing; it tells you who would have been refused.
- **Deny** refuses the request with the policy's message. RBAC is unchanged either way: `oc auth can-i` keeps saying
  "yes" to an edit holder, because admission runs after authorization. Only a real or `--dry-run=server` write shows
  the refusal.
- **Evaluation errors** follow the mode on Kyverno 1.16.1 (measured, recorded in the writers policy's header): in
  Audit the error is recorded as `result="error"` and the write goes through; in Deny the request is refused. The
  CRD's own description of `failurePolicy` says it also covers CEL runtime errors; the measured 1.16.1 behaviour is
  that the mode decided the outcome with `failurePolicy: Fail`, and `Ignore` was not measured. For the writers policy
  the only error path is the SubjectAccessReview call, reached only by requesters the name, group and
  service-account checks did not settle.
- **No verdict at all** (admission controller down or past `timeoutSeconds: 10`) is governed by `failurePolicy`
  alone. The writers policy sets `Fail`: while Kyverno is unavailable, nobody it matches can write those CRs,
  administrators and service accounts included. The sandbox runs one admission replica, so every Kyverno restart
  is such a window; check the admission controller's replica count and rollout settings on a real cluster before
  relying on it.

## Procedure for the session's policy: `restrict-nco-config-writers`

Preconditions, in this order.

1. **The companion VAP is applied and enforcing.** Kyverno exempts its own namespace from its own policies, and the
   tiers this policy restricts hold `edit` there, so without the VAP they could disable the policy by editing the
   `kyverno/kyverno` ConfigMap or the Deployment. Check:
   ```sh
   oc get validatingadmissionpolicybinding protect-kyverno-configuration -o jsonpath='{.spec.validationActions}{"\n"}'
   # expect: ["Deny"]
   ```
2. **The allow-list is complete.** Every legitimate writer of NamespaceConfig, GroupConfig, UserConfig and GroupSync
   must be one of: a cluster-admin (by name, by a group matching `app-ocp-rbac-*-cluster-admin`, or by
   SubjectAccessReview), a group named in `namedPlatformAdminGroups`, the operator's service account, the
   group-sync operator's service account, or the GitOps application controller. A CI service account that applies
   CRs directly is the typical omission. Add exact group names to `namedPlatformAdminGroups` in the policy (the same
   list exists in the VAP; keep them equal).
3. **The Audit soak is clean.** Over the observation period, every PolicyViolation event naming the policy must be a
   writer you intend to refuse, and the error counter must stay at zero:
   ```sh
   oc get events -A --field-selector reason=PolicyViolation \
     -o custom-columns=WHEN:.lastTimestamp,OBJECT:.involvedObject.name,MSG:.message | grep restrict-nco-config-writers
   # Prometheus, if scraped:
   # kyverno_validating_policy_execution_duration_seconds_count{policy_name="restrict-nco-config-writers",result="fail"}
   # kyverno_validating_policy_execution_duration_seconds_count{policy_name="restrict-nco-config-writers",result="error"}  # must be 0
   ```
   On the sandbox on 2026-09-05 the event list for the policy was empty apart from the verify script's own probes.
4. **The verify script passes in Audit** (it reads the mode from the cluster and expects the Audit outcomes; needs a
   cluster-admin login and `jq`, per its header; it has no flags):
   ```sh
   working-sessions/scripts/verify-nco-writer-policy.sh
   ```

The switch.

```sh
# 1. one field, in the file that already exists (BSD/macOS sed; on GNU sed write `sed -i` without the '' —
#    GNU sed reads '' as an empty script and the file is left unchanged)
sed -i '' 's/^  validationActions: \[Audit\]$/  validationActions: [Deny]/' \
  working-sessions/policies/kyverno-restrict-nco-writers.yaml
git diff --stat   # exactly one line

# 2. apply, then wait for the single admission replica to load the new mode
oc apply -f working-sessions/policies/kyverno-restrict-nco-writers.yaml
oc get validatingpolicy restrict-nco-config-writers -o jsonpath='{.spec.validationActions}{"\n"}'   # ["Deny"]
sleep 20

# 3. prove it: the script now expects "denied the request" for the refused identities
working-sessions/scripts/verify-nco-writer-policy.sh
```

Measured on the sandbox: after a mode change the replica takes several seconds to settle, and a run inside that
window mixes outcomes; the script's settled results were 29 checks passing in Audit and 28 in Deny (the Audit run has
one extra check, the count of violation events). Commit the one-line change on its own branch and open a PR: the
mode is part of the record, not a cluster-only setting.

Rollback is the same edit in reverse (`[Deny]` to `[Audit]`), applied the same way. Nothing else changes. A mode
change is admission-only: existing NamespaceConfig, GroupConfig, UserConfig and GroupSync objects are not mutated or
deleted when `validationActions` flips, and neither are the RoleBindings the operator already rendered. That is true
of any validate policy, the ClusterPolicies with `background: true` included (a background scan only adds
PolicyReport rows). This policy's `background` is off for a different reason, recorded in its header:
`request.userInfo` exists only on an admission request, and the rule is about the writer, not the object.

## The four older ClusterPolicies

They are not part of the operator work. Three were added on 2026-07-30; `kyverno-validation-only.yaml` dates to
2026-03-16 and was reworked on 2026-07-30. Each is switched the same way, **one file at a time and only after its own
soak is clean**, with `Enforce` in place of `Audit`. None of the four sets
`validate.failureAction` on a rule today, so the top-level field is enough; if a rule later sets it, that value wins
and a top-level edit will not move that rule. Check before each switch for a KEY named `failureAction` or
`failureActionOverrides` (not the substring inside `validationFailureAction`; `-E` so the alternation works on both
BSD and GNU grep):

```sh
grep -nE '^ +(failureAction|failureActionOverrides):' working-sessions/policies/<one-file>.yaml   # expect no output
```

The soak signal for these is their PolicyReport rows, because `background: true` scans existing objects, not only new
writes. The summary view hides the rows; list the FAIL and ERROR results with their subjects:

```sh
oc get clusterpolicyreport,policyreport -A -o json | jq -r '.items[] as $r | ($r.results // [])[]
  | select(.result == "fail" or .result == "error")
  | [($r.scope.kind // ""), ($r.scope.namespace // ""), ($r.scope.name // ""), .policy, .rule, .result] | @tsv'
```

Measured on the sandbox on 2026-09-05: `group-naming-app-ocp-rbac` 18 FAIL rows (its header records 15 groups whose
mnemonics are 5 to 8 letters and says Enforce would make group-sync fail creating them until they are renamed or the
pattern widened), `rbac-standards-enforcement` 21, `group-naming-bda-rbac` 1, `namespace-oud-group-allowlist` 1
(namespace `oud-poc-platform`). Two cautions about reading those rows:

- **An existing violator is not refused on its next update by default.** The file does not set
  `allowExistingViolations` on `validate-oud-group-known-family`, and the live rule reads `allowExistingViolations: true`
  (the CRD's default, measured with `oc get clusterpolicy namespace-oud-group-allowlist -o jsonpath=...`), so an UPDATE
  that leaves a pre-existing violation in place is admitted in Enforce; a CREATE of a new violating object is refused. Refusing
  updates to already-violating objects is a separate, explicit decision: set that rule's `allowExistingViolations` to
  `false`.
- **Rows can be stale.** `kyverno-validation-only.yaml` documents that a resource which becomes excluded keeps its
  failure in the report until the reports are regenerated (`oc delete clusterpolicyreport --all`, which Kyverno
  rebuilds).

The switch, per file (BSD/macOS `sed`; GNU: `sed -i` without the `''`):

```sh
f=working-sessions/policies/<one-file>.yaml
# kyverno-validation-only.yaml carries a comment on the same line; replace the whole line so it does not go stale
sed -i '' -e 's/^  validationFailureAction: Audit  # Start with Audit, can change to Enforce later$/  validationFailureAction: Enforce  # Audit reports; Enforce refuses/' \
          -e 's/^  validationFailureAction: Audit$/  validationFailureAction: Enforce/' "$f"
git diff --stat "$f"    # exactly one line
oc apply -f "$f"
```

## What is not needed

- No new manifest, no Helm value, no chart change. The policies are applied by hand from `working-sessions/policies/`
  (the root README's install steps), and the mode lives in each file.
- No RBAC change. The policies add an admission-time check; the OLM-aggregated `admin` and `edit` roles keep their
  verbs on the CRDs.
- No operator change. The operator's own service account is on the allow-list and writes `/status` through the
  subresource the policy does not match; its finalizer UPDATE on the CR is allowed by name.
