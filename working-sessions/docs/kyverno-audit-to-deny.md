# Turning the Kyverno policies from Audit to Deny

Companion to `working-sessions/policies/kyverno-restrict-nco-writers.yaml` and the older ClusterPolicies in the same
directory. Everything below was measured on the sandbox (Kyverno 1.16.1, one admission-controller replica) on
2026-09-05; the policy headers hold the detailed reasoning and this guide holds the procedure.

## The short answer

**No new YAML.** Each policy switches mode by changing one field in the file it already lives in, re-applying that
file, and running the verification that belongs to it. The companion ValidatingAdmissionPolicy is already enforcing.

| Policy (file) | Kind | Field to change | Today | Enforcing value |
|---|---|---|---|---|
| `kyverno-restrict-nco-writers.yaml` (`restrict-nco-config-writers`) | `policies.kyverno.io/v1beta1` ValidatingPolicy | `spec.validationActions` | `[Audit]` | `[Deny]` |
| `vap-protect-kyverno-configuration.yaml` (`protect-kyverno-configuration`) | `admissionregistration.k8s.io/v1` ValidatingAdmissionPolicy + Binding | `spec.validationActions` on the **Binding** | `[Deny]` | already `[Deny]` |
| `kyverno-group-naming-app-ocp-rbac.yaml` (`group-naming-app-ocp-rbac`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |
| `kyverno-group-naming-bda-rbac.yaml` (`group-naming-bda-rbac`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |
| `kyverno-namespace-oud-group.yaml` (`namespace-oud-group-allowlist`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |
| `kyverno-validation-only.yaml` (`rbac-standards-enforcement`) | `kyverno.io/v1` ClusterPolicy | `spec.validationFailureAction` | `Audit` | `Enforce` |

Two vocabularies, one meaning. The CEL policy types (ValidatingPolicy, ValidatingAdmissionPolicy) take a list,
`validationActions`, whose enforcing value is `Deny` (the live CRD also offers `Warn`, a header the client sees while
the request is admitted). The kyverno.io/v1 ClusterPolicy takes a scalar, `validationFailureAction`, whose enforcing
value is `Enforce` (the live CRD: "values are Audit or Enforce"; the top-level field is marked deprecated in favour of
`validate.failureAction` per rule, and still honoured on 1.16.1). Writing `Deny` into a ClusterPolicy is rejected by
the schema; writing `Enforce` into a ValidatingPolicy is too.

## What Deny changes, and what it does not

- **Audit** admits the request and records a PolicyViolation event (and a PolicyReport row for the ClusterPolicies).
  A policy in Audit protects nothing; it tells you who would have been refused.
- **Deny** refuses the request with the policy's message. RBAC is unchanged either way: `oc auth can-i` keeps saying
  "yes" to an edit holder, because admission runs after authorization. Only a real or `--dry-run=server` write shows
  the refusal.
- **Evaluation errors** behave differently by mode (measured, recorded in the writers policy's header): in Audit an
  error is recorded as `result="error"` and the write goes through; in Deny the request is refused. For the writers
  policy the only error path is the SubjectAccessReview call, and it is reached only by requesters the name, group
  and service-account checks did not settle.
- **No verdict at all** (admission controller down or past `timeoutSeconds: 10`) is governed by `failurePolicy`, not
  by the mode. The writers policy sets `Fail`: while Kyverno is unavailable, nobody it matches can write those CRs,
  administrators and service accounts included. With one admission replica, every Kyverno restart is such a window.
  That is the intended failure for rarely-changed platform configuration; know it before flipping.

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
4. **The verify script passes in Audit** (it reads the mode from the cluster and expects the Audit outcomes):
   ```sh
   working-sessions/scripts/verify-nco-writer-policy.sh
   ```

The switch.

```sh
# 1. one field, in the file that already exists
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

Rollback is the same edit in reverse (`[Deny]` to `[Audit]`), applied the same way. Nothing else changes; existing
CRs and the objects the operator manages are untouched in both directions because the policy is about the writer,
not the object (`background: false`).

## The four older ClusterPolicies

They are not part of the operator work and were added earlier (2026-07-30). Each is switched the same way, in its own
file, with `Enforce` in place of `Audit`:

```sh
sed -i '' 's/^  validationFailureAction: Audit/  validationFailureAction: Enforce/' \
  working-sessions/policies/kyverno-group-naming-app-ocp-rbac.yaml \
  working-sessions/policies/kyverno-group-naming-bda-rbac.yaml \
  working-sessions/policies/kyverno-namespace-oud-group.yaml \
  working-sessions/policies/kyverno-validation-only.yaml
oc apply -f <each file>
```

Before flipping any of them, read its PolicyReport rows: `oc get clusterpolicyreport,policyreport -A` lists PASS,
FAIL and ERROR per subject. On the sandbox on 2026-09-05 the namespace `oud-poc-platform` had 2 FAIL rows, so
`namespace-oud-group-allowlist` in Enforce would refuse the next write to that namespace until its labels are fixed;
that is what the soak is for. These policies have `background: true`, so their reports cover existing objects, not
only new writes, which is the signal to use.

## What is not needed

- No new manifest, no Helm value, no chart change. The policies are applied by hand from `working-sessions/policies/`
  (the root README's install steps), and the mode lives in each file.
- No RBAC change. The policies add an admission-time check; the OLM-aggregated `admin` and `edit` roles keep their
  verbs on the CRDs.
- No operator change. The operator's own service account is on the allow-list and writes `/status` through the
  subresource the policy does not match; its finalizer UPDATE on the CR is allowed by name.
