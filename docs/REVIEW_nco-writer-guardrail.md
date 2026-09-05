# Review — the Kyverno guardrail on who may write the operator's CRs (PR #23)

Adversarial second-opinion passes, 2026-09-05, on `working-sessions/policies/kyverno-restrict-nco-writers.yaml`
and `working-sessions/scripts/verify-nco-writer-policy.sh`. Reviewers: Cursor (Grok 4.6 high fast, ask mode,
traced from source, no cluster) and Codex (gpt-5.6-sol, xhigh), which produced no report: its read-only sandbox
could not fetch Kyverno's source and it spent over an hour in web searches before being stopped. Every verdict was
re-measured here on the sandbox cluster (Kyverno 1.16.1, OpenShift 4.x). Briefs and raw outputs: session
scratchpad `adv/review_brief_kyverno*.md`, `adv/review_cursor_kyverno*.txt`.

## First pass (commit 6ce0d47-era head, before the fixes)

| Claim | Cursor | Decision |
|---|---|---|
| C1 CEL valid; variables lazy so the SubjectAccessReview is posted only when the names do not settle | PLAUSIBLE (source not fetchable) | **Confirmed by source and measurement**: Kyverno v1.16.1 `pkg/cel/policies/vpol/compiler/policy.go` builds `variables` with `lazy.NewMapValue`; on the cluster, with the review call deliberately broken (a bogus resource), `system:admin` was still allowed, a User bound directly to cluster-admin refused with "failed to load context". Cursor's inlining of the review into the validation rejected: unnecessary once laziness is measured, and less readable |
| C2 the allow-list admits exactly the named identities | CONFIRMED | — (Cursor cited the chart's Jobs: none write these CRs) |
| C3 failurePolicy Fail cannot lock admins out except while Kyverno is down | PLAUSIBLE | **Accepted as a doc correction**: a failing review call refuses exactly the requesters that needed it (a User bound directly to cluster-admin) while Kyverno is up; name-settled identities are unaffected. Measured and written in the header's FAILURE MODES |
| C4 the rule matches the CRs and not /status | CONFIRMED | — |
| C5 the script's classification and exit behaviour | CONFIRMED | — |
| C6 documentation matches the code | REFUTED | **Accepted**: the header said "a synced group in the tier" while the CEL accepted any group ending in `-cluster-admin`. The CEL now requires the chart's family prefix (`app-ocp-rbac-`); measured in Deny: `evil-cluster-admin` refused, `app-ocp-rbac-alpha-cluster-admin` allowed. The header states what the CEL does (it trusts `request.userInfo.groups`, looks nothing up) and why that is safe (an edit holder can neither create nor update Groups; impersonation needs the impersonate verb). TESTING now mentions UPDATE; the README paragraph says "measured" |

**Volunteered by Cursor, accepted:** the script did not assert the Audit-mode events its own header promised. It
now counts the writes it expected Audit to refuse and requires that many PolicyViolation events naming the policy
since the run began, retrying a few seconds for Kyverno's asynchronous emission. Measured: 3 events for 3 refused
writes; 22 checks pass in Audit, 21 in Deny.

**Volunteered by Cursor, refuted by measurement:** that the operator's service account name was unverified. The
deployment's `serviceAccountName` is `controller-manager` in namespace `namespace-configuration-operator`
(`oc get deploy ... -o jsonpath`), and the script proves that identity allowed on CREATE, UPDATE and DELETE.

## Measurements the design rests on

| requester (group) | bound ClusterRole | create NC | delete NC | `can-i '*' '*'` |
|---|---|---|---|---|
| `app-ocp-rbac-alpha-cluster-admin` | admin | yes | yes | no |
| `app-ocp-rbac-alpha-cluster-developer` | edit | yes | yes | no |
| `app-ocp-rbac-alpha-cluster-audit` | view | no | no | no |
| `app-ocp-rbac-alpha-ns-admin` | (namespaced) | no | no | no |
| `kubeadmin` (User bound to cluster-admin) | cluster-admin | yes | yes | yes |

OLM's aggregated ClusterRoles `namespaceconfigs.redhatcop.redhat.io-v1alpha1-admin` and `-edit` exist with the
aggregation labels. The edit tier cannot create or update `groups.user.openshift.io`. Kyverno's admission
controller may create SubjectAccessReviews. `policies.kyverno.io` serves v1alpha1 and v1beta1; PolicyException is
disabled on this cluster, so exemptions live in the policy.

## Second pass (2d0665e)

Pending: the family-prefix expression against pathological group names, the FAILURE MODES paragraph against the
YAML, the script's event assertion (timestamp comparison, counting) and exit status.
