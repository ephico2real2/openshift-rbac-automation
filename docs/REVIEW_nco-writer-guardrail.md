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

## Second pass (2d0665e), Cursor

| Claim | Cursor | Decision |
|---|---|---|
| C1 the family-prefix pattern admits exactly the tier | REFUTED (`app-ocp-rbac--cluster-admin`, `app-ocp-rbac-x-cluster-admin-cluster-admin` pass) | **Rejected on the operator's design, then measured**: the chart's live GroupConfig guards on `hasSuffix "-cluster-admin" .Name` alone over synced groups; GroupSync pulls every LDAP group matching `cn=app-ocp-rbac-*`; live mnemonics run 4 to 8 letters; the naming policy is Audit-only. One CR capturing every group that fits the pattern is the design, so the exemption is the chart's grant narrowed by the family prefix; a full-name regex would be narrower than the grant itself and could refuse a legitimate synced admin group. The reasoning is written next to the expression |
| C2 FAILURE MODES describes the YAML | REFUTED | **Accepted**: a webhook timeout is the API server applying Fail to the whole request (everyone refused, including name-settled identities); only a failed review call refuses just those who needed it; and (as first written here, then corrected by the third reviewer below) in Audit an evaluation error is NOT refused: the write goes through and the policy records result="error". Rewritten as three paths |
| C3 the event assertion's time comparison | REFUTED | **Accepted**: an `eventTime` with a fraction sorts below a whole-second `since` as text when the seconds are equal (measured offline with jq: the in-window event was dropped). Timestamps are cut to whole seconds before comparing; an event with no timestamp still cannot match |
| C4 exit status under `set -euo pipefail` | REFUTED | **Accepted**: a failing `oc get events` inside the assignment would end the script before "result:"; it now counts as no events |

**Volunteered, accepted:** the script pins a `-cluster-admin` suffix from another family as refused
(`evil-cluster-admin`); the comment on the current-login check says an impersonated name carries no groups.
**Volunteered, rejected:** a second look-alike check (`app-ocp-rbac-x-cluster-admin-cluster-admin`) that the
pattern admits by design.

**Measured while re-verifying:** after a mode switch the single Kyverno admission replica takes several seconds
to settle, during which requests see either mode; a run started within that window reports mixed results. The
verify script is meant to run well after applying; the record's numbers come from settled runs: 25 checks in
Audit (12 PolicyViolation events for the 6 refused writes), 24 in Deny. Codex produced no second-pass report
either; a first-principles Fable 5.1 reviewer's report is recorded below when it lands.

## Third opinion (a9ebcb2), first-principles reviewer on Fable 5.1 with experiments on the cluster

| Finding | Decision |
|---|---|
| F1 the restricted tiers can switch the policy off: they hold `edit` on the `kyverno` namespace, Kyverno's request filter runs before any policy, and Kyverno exempts its own namespace (`[*/*,kyverno,*]`) from every Kyverno policy | **Re-measured, accepted**: the developer tier's server dry run patched the `kyverno` ConfigMap and scaled the admission controller to zero; no policy on the cluster or in the repository covers that namespace. A Kyverno policy cannot close it; the companion `vap-protect-kyverno-configuration.yaml` (the API server's own admission, same wildcard-authorizer criterion, Kyverno's own service accounts allowed) does, in Deny. Measured below |
| F2 the refusal on an evaluation error is the Deny action, not `failurePolicy`; in Audit an error is allowed | **Accepted, and the sentence I had added in the second pass is retracted**: measured by the reviewer with the error counter (kubeadmin allowed in Audit while `result="error"` moved). FAILURE MODES rewritten as three paths |
| F3 the ROLLOUT metric selector `result="FAIL"` matches nothing (live labels are lowercase) | **Accepted** |
| F4 OLM aggregates `groupsyncs` into `edit` too; an edit holder could author a GroupSync (provider, URL and credentials Secret live in the CR) that mints an `app-ocp-rbac-*-cluster-admin` group containing themselves | **Re-measured, accepted**: `edit` carries create/update/patch/delete on groupsyncs; the developer tier may create Secrets in the group-sync namespace. GroupSync CRs are now guarded; the group-sync operator's service account (`controller-manager` in `group-sync-operator`, which may update its CRs) is allow-listed |
| F5 the script's current-login check impersonates a name without its groups | **Accepted**: the groups come from a SelfSubjectReview (measured working on this server) |
| F6 the second-pass fixes to the event check verified; residual: a concurrent run's events could mask a missing one | Recorded, acceptable for a sandbox script |

**Measured after applying the third-opinion changes (settled runs):** the companion in Deny refuses the developer
tier's patch of the `kyverno` ConfigMap and its scale of the admission controller, refuses the `-cluster-admin`
tier (the `admin` ClusterRole has no wildcard), allows kubeadmin, and leaves a ConfigMap in another namespace
alone; a developer's annotate on a GroupSync is refused, the group-sync operator's service account and kubeadmin
allowed. The verify script: 26 checks in Deny, 27 in Audit (6 PolicyViolation events for the 6 refused writes, and
both companion checks).

**Operator's correction after the third opinion:** the `-cluster-admin` tier (`app-ocp-rbac-<mnemonic>-cluster-admin`)
is the trusted platform-admin population by the chart's design, so the companion must not lock it out of Kyverno's
configuration; it now carries the guardrail's pattern exemption. Measured: the tier's patch of the `kyverno`
ConfigMap allowed, the developer tier still refused.

## Third pass on the companion (85019e9), Cursor

| Claim | Cursor | Decision |
|---|---|---|
| C1 the `authorizer` check asks the API server for verb `*` on resource `*` in group `*`, cluster-scoped | CONFIRMED (the strings are literal attribute values; RBAC's `*` in a rule is what matches them) | — |
| C2 the namespace selector and `deployments/scale` semantics; no bypass by omitting the namespace | CONFIRMED | — |
| C3 the `system:serviceaccount:kyverno:` prefix is an identity the restricted tier can mint | PLAUSIBLE (no cluster) | **Re-measured, accepted**: the developer tier may create ServiceAccounts, Pods, tokens and exec in the kyverno namespace, and Kyverno's background controller holds update on ConfigMaps there. None of Kyverno's accounts has ever written the ConfigMap or the Deployments (managers: helm, kubectl, and kube-controller-manager through the status subresource only). The exemption is removed; measured: the background controller's account and a forged account are refused, Kubernetes' controllers write through `/status`, which the policy does not match |
| C4 `failurePolicy` semantics for a VAP and the risk to Helm, OLM, Kyverno's own writes | CONFIRMED | — |
| C5 GroupSync is namespaced, status writes unmatched, the operator's `SetDefaults` updates the main resource | CONFIRMED (cited from the group-sync-operator source) | the allow-list of the group-sync operator's account is load-bearing |

**Volunteered, accepted:** the API server's refusal reads "denied request" where Kyverno's reads "denied the
request"; the script's classifier now recognises both (the live run had passed through the error branch by luck).
A forged Kyverno account is pinned as refused.

**Operator's addition:** both policies now carry `namedPlatformAdminGroups`, an explicit list of groups allowed by
exact name next to the tier pattern. Measured with a temporary list: a member holding edit plus the named group
patched Kyverno's ConfigMap and created a NamespaceConfig in Deny while the developer tier was refused in both;
with the shipped empty list the same identity is a plain edit holder. Settled runs: 29 checks in Audit, 28 in Deny.
