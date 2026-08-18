# Baseline — chart 0.19.1 at `1bb5ef8`, measured BEFORE any review change

Captured so every claim in `REVIEW_chart_0.19.1.md` can be judged against what the chart and the cluster
actually did beforehand, rather than against anyone's recollection. A fix that claims "no behaviour
change" is checked by re-running the commands below and diffing these numbers.

**Nothing here is aspirational.** Every value was produced by the command printed beside it.

## Identity

| | |
|---|---|
| commit | `1bb5ef8d8364b2513fe05e6e6d6534100cea6f62` |
| branch | `feat/oud-group-multiple-policies` |
| chart version | **0.19.1** (appVersion 1.2.6) |
| CI run | [32108508346](https://github.com/ephico2real2/openshift-rbac-automation/actions/runs/32108508346) — **success**, all 9 steps |
| live release | `nco` in `namespace-configuration-operator`, **rev 19**, deployed |

## Rendered output — the fingerprints

`helm template` is **deterministic** here: two consecutive runs of each combination produced identical
hashes, which is what makes a hash usable as an anchor at all.

```sh
helm template nco charts/namespace-configuration-operator | shasum -a 256
helm template nco charts/namespace-configuration-operator \
  -f charts/namespace-configuration-operator/crc-values.yaml | shasum -a 256
```

Hash the command's output **byte for byte** — piped straight into `shasum`, with nothing stripped. The
first version of this file hashed the output after trimming trailing whitespace and produced two digests
that the documented commands could never reproduce. A baseline nobody can re-derive is worse than none.

| combination | resources | sha256 |
|---|---|---|
| defaults | 22 | `a74fc4d9bc00b94eb08935a6d6a9cc9464a7a6b74d29b81e7b420743445edad6` |
| crc overlay | 24 | `5080dd42f7c182ba109d8b14082fb53b80bf538f241ab136fe4bbad578daed6f` |

### Wave and hook-weight inventory (crc overlay)

The ordering `check-ordering.py` asserts. The policy CRs at wave 3 sit **above** the Subscription at 0,
because ArgoCD deletes in reverse wave order — the operator has to outlive the CRs whose finalizers
revoke the children.

```
KIND                   NAME                                            WAVE HOOK-WEIGHT
ServiceAccount         namespace-configuration-operator-image-overrid     1 -
ServiceAccount         namespace-configuration-operator-installplan-a     1 -
ServiceAccount         namespace-configuration-operator-orphan-sweepe     1 -
ConfigMap              namespace-configuration-operator-image-overrid     1 -
ConfigMap              namespace-configuration-operator-installplan-a     1 -
ConfigMap              namespace-configuration-operator-orphan-sweepe     1 -
ClusterRole            namespace-configuration-operator-orphan-sweepe     1 -
ClusterRoleBinding     namespace-configuration-operator-orphan-sweepe     1 -
Role                   namespace-configuration-operator-image-overrid     1 -
Role                   namespace-configuration-operator-installplan-a     1 -
RoleBinding            namespace-configuration-operator-image-overrid     1 -
RoleBinding            namespace-configuration-operator-installplan-a     1 -
CronJob                namespace-configuration-operator-image-overrid     2 -
GroupConfig            baseline-cluster-rbac                              3 -
GroupConfig            custom-cluster-rbac                                3 -
NamespaceConfig        baseline-nonprod-rbac                              3 -
NamespaceConfig        baseline-prod-rbac                                 3 -
NamespaceConfig        bdp-oud-group-rbac                                 3 -
OperatorGroup          namespace-configuration-operator                  -1 -
Subscription           namespace-configuration-operator                   0 -
Job                    namespace-configuration-operator-image-overrid     2 10
Job                    namespace-configuration-operator-image-overrid     1 0
Job                    namespace-configuration-operator-installplan-a     1 5
Job                    namespace-configuration-operator-orphan-sweepe     4 20
```

## Live cluster — the children the operator created

These carry **no Helm metadata and no ownerReferences** — 0 of 42 on both counts. Helm owns the 5 CRs;
nothing but the operator's finalizer and the sweeper ever touches these.

| | |
|---|---|
| total | **42** — 26 RoleBinding, 13 ClusterRoleBinding, 3 Role |
| identity sha256 | `c5273b285a3070cc56e467de21f7c8172cd157c421b64059ba883322bc870283` |
| UID-list sha256 | `60fdb583bc83cbe1fad3dccf732b4b65f2e66f70b1276d7186f537560477d7f0` |

**The UID hash is the one that matters.** A name-level diff cannot see a delete-and-recreate — which is
exactly how the 0.19.1 sweeper bug stayed hidden while it revoked access on every single sync.

```sh
oc get rolebinding,clusterrolebinding,role -A \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator \
  -o jsonpath='{range .items[*]}{.kind}|{.metadata.namespace}|{.metadata.name}|{.metadata.labels.rbac\.ocp\.io/config-source}|{.metadata.uid}{"\n"}{end}' \
  | sort | cut -d'|' -f5 | shasum -a 256
```

### Objects per policy CR

| CR | objects |
|---|---|
| `baseline-cluster-rbac` | 12 |
| `baseline-nonprod-rbac` | 20 |
| `baseline-prod-rbac` | 3 |
| `bdp-oud-group-rbac` | 6 |
| `custom-cluster-rbac` | 1 |

## Grants, proved with `oc auth can-i`

| group | namespace | check | result |
|---|---|---|---|
| `app-ocp-rbac-spar-ns-audit` | `oud-poc-crossfamily` | `create pods` | **yes** |
| `app-ocp-rbac-spar-ns-audit` | `oud-poc-crossfamily` | `get pods` | **yes** |
| `app-ocp-rbac-beta-ns-audit` | `beta-prod` | `get pods` | **yes** |
| `app-ocp-rbac-beta-ns-audit` | `beta-prod` | `delete pods` | **no** |

The last two together ARE the security model: prod audit binds `view`, so it reads and cannot write. A
change that turns that `no` into a `yes` is a privilege escalation, not a fix.

Note for anyone re-running these: pass the verb and resource as separate arguments. zsh does not
word-split an unquoted expansion, so a `$verb` holding `"create pods"` arrives as one argument and
`oc` rejects it — the error looks like a broken permission check but is a broken command.

## Checks that pass at this commit

```sh
helm lint charts/namespace-configuration-operator                        # 1 chart linted, 0 failed
working-sessions/scripts/check-ordering.py             # OK on all four invariants
```

Ordering verdict: **24 documents across 18 template files, every one declaring a wave; 24 rendered
resources, 0 missing**; policy CRs above the Subscription; the sweep after them; no two hooks sharing a
weight.

## What counts as a regression against this baseline

1. The **UID hash changes** after an operation that should not have touched children. Something was
   deleted and rebuilt, and the object counts will not show it.
2. A **`can-i` answer flips**, either direction. `no` to `yes` is escalation; `yes` to `no` is a grant
   silently revoked.
3. The **object total or the per-CR split** moves without a values change that accounts for it.
4. The **rendered hash changes** on work that was supposed to be comment-only. Comments live inside the
   rendered manifests, so condensing them WILL move the hash — re-baseline deliberately and let a diff
   of the rendered YAML carry the proof that only comments moved.
5. `check-ordering.py` or `helm lint` stops passing.

Point 4 is the one to watch during the comment pass: the hash moving is expected there, so it stops
being evidence and the YAML diff has to do the work instead.

## Appendix — the 42 children

`kind | namespace | name | config-source`. UIDs omitted deliberately; the hash above covers them and
they change on every legitimate rebuild.

```
ClusterRoleBinding |  | app-ocp-rbac-alpha-cluster-admin-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-alpha-cluster-audit-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-alpha-cluster-developer-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-alpha-database-admin-crb | custom-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-demo-cluster-admin-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-demo-cluster-audit-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-demo-cluster-developer-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-devops-cluster-admin-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-finance-cluster-developer-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-newteam-cluster-admin-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-platform-cluster-admin-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-platform-cluster-developer-crb | baseline-cluster-rbac
ClusterRoleBinding |  | app-ocp-rbac-test-cluster-admin-crb | baseline-cluster-rbac
Role | oud-poc-crossfamily | spark-job-submitter-role | bdp-oud-group-rbac
Role | oud-poc-platform | spark-job-submitter-role | bdp-oud-group-rbac
Role | oud-poc-trino | spark-job-submitter-role | bdp-oud-group-rbac
RoleBinding | beta-prod | beta-audit-rb | baseline-prod-rbac
RoleBinding | beta-rnd | beta-audit-rb | baseline-nonprod-rbac
RoleBinding | beta-rnd | beta-developer-rb | baseline-nonprod-rbac
RoleBinding | beta-uat | beta-audit-rb | baseline-nonprod-rbac
RoleBinding | beta-uat | beta-developer-rb | baseline-nonprod-rbac
RoleBinding | demo-prod | demo-audit-rb | baseline-prod-rbac
RoleBinding | demo-production | demo-audit-rb | baseline-prod-rbac
RoleBinding | demo-qa | demo-audit-rb | baseline-nonprod-rbac
RoleBinding | demo-qa | demo-developer-rb | baseline-nonprod-rbac
RoleBinding | demo-rnd | demo-audit-rb | baseline-nonprod-rbac
RoleBinding | demo-rnd | demo-developer-rb | baseline-nonprod-rbac
RoleBinding | demo-uat | demo-audit-rb | baseline-nonprod-rbac
RoleBinding | demo-uat | demo-developer-rb | baseline-nonprod-rbac
RoleBinding | jeff-qa | jeff-audit-rb | baseline-nonprod-rbac
RoleBinding | jeff-qa | jeff-developer-rb | baseline-nonprod-rbac
RoleBinding | jeff-rnd | jeff-audit-rb | baseline-nonprod-rbac
RoleBinding | jeff-rnd | jeff-developer-rb | baseline-nonprod-rbac
RoleBinding | klt-fail-mnemonic-toolong | toolongx-audit-rb | baseline-nonprod-rbac
RoleBinding | klt-fail-mnemonic-toolong | toolongx-developer-rb | baseline-nonprod-rbac
RoleBinding | klt-pass-both | klta-audit-rb | baseline-nonprod-rbac
RoleBinding | klt-pass-both | klta-developer-rb | baseline-nonprod-rbac
RoleBinding | klt-pass-mnemonic-3char | klt-audit-rb | baseline-nonprod-rbac
RoleBinding | klt-pass-mnemonic-3char | klt-developer-rb | baseline-nonprod-rbac
RoleBinding | oud-poc-crossfamily | app-ocp-rbac-spar-ns-audit-rb | bdp-oud-group-rbac
RoleBinding | oud-poc-platform | app-ocp-rbac-platform-ns-admin-rb | bdp-oud-group-rbac
RoleBinding | oud-poc-trino | bda-rbac-trino-alpha-users-rb | bdp-oud-group-rbac
```
