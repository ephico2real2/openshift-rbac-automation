# openshift-rbac-automation — Helm chart

A customized [Red Hat CoP Namespace Configuration Operator](https://github.com/redhat-cop/namespace-configuration-operator)
(NCO), packaged as a Helm chart together with our own RBAC policies. It installs the operator on
OpenShift via OLM — a namespace, an AllNamespaces OperatorGroup, and a Subscription, optionally
running a custom operator build — and deploys the policies (`NamespaceConfig` / `GroupConfig`
custom resources) from `values.yaml`, one flag per policy. The raw manifests under
[`../../working-sessions/policies`](../../working-sessions/policies) are the readable reference for those policies, not something to apply.

## What it creates

| Resource | Name | Notes |
|---|---|---|
| `Namespace` | `namespace-configuration-operator` | pre-install hook; skip with `createNamespace=false` |
| `OperatorGroup` | `namespace-configuration-operator` | **AllNamespaces** (empty spec); skip with `createOperatorGroup=false` |
| `Subscription` | `namespace-configuration-operator` | channel `alpha`, source `community-operators` |

### Why AllNamespaces?

NCO reconciles namespaces cluster-wide, so its OperatorGroup must watch **every**
namespace. In OLM that means an OperatorGroup with **no `targetNamespaces`** (an empty
spec). This is the key difference from a namespace-scoped operator, which lists specific
`targetNamespaces`.

> If you install into a namespace that already has a global OperatorGroup (e.g.
> `openshift-operators`), set `createOperatorGroup=false` — two global OperatorGroups in
> one namespace is an OLM conflict.

## Install

```bash
# Default: dedicated namespace + global OperatorGroup + Subscription
helm install nco ./chart

# Into the built-in openshift-operators namespace (already has a global OperatorGroup):
helm install nco ./chart \
  --set namespace=openshift-operators \
  --set createNamespace=false \
  --set createOperatorGroup=false
```

## Verify

```bash
oc get csv -n namespace-configuration-operator | grep namespace-configuration-operator
oc get pods -n namespace-configuration-operator
oc get crd | grep redhatcop.redhat.io   # groupconfigs, namespaceconfigs, ...
```

Then apply the policies:

```bash
oc apply -f ../policies/
```

## Configuration

| Key | Description | Default |
|---|---|---|
| `namespace` | Install namespace (operator watches all namespaces regardless) | `namespace-configuration-operator` |
| `createNamespace` | Create the install namespace | `true` |
| `createOperatorGroup` | Create the AllNamespaces OperatorGroup | `true` |
| `subscription.packageName` | Catalog package name | `namespace-configuration-operator` |
| `subscription.channel` | Update channel | `alpha` |
| `subscription.source` | CatalogSource | `community-operators` |
| `subscription.sourceNamespace` | CatalogSource namespace | `openshift-marketplace` |
| `subscription.installPlanApproval` | `Automatic` or `Manual` | `Manual` |
| `subscription.startingCSV` | Pin the initial CSV; also the approval authority (empty = channel head) | `namespace-configuration-operator.v1.2.6` |
| `subscription.autoApproveInstallPlan.enabled` | Approve only the pinned CSV's InstallPlan, so `Manual` still installs unattended | `true` |
| `subscription.autoApproveInstallPlan.csv` | CSV to approve; empty = use `startingCSV` | `""` |
| `subscription.autoApproveInstallPlan.waitSeconds` | Wait for the InstallPlan to appear, then to reach `Complete` | `300` |
| `subscription.zapLogLevel` | Operator log verbosity (`ZAP_LOG_LEVEL`) | `info` |
| `subscription.zapDevel` | Development-mode logging (`ZAP_DEVEL`) | `"false"` |
| `subscription.relatedImageManager` | `RELATED_IMAGE_MANAGER` env — does NOT override this operator's image (tested); off by default | `""` |
| `subscription.extraEnv` | Extra env appended to `spec.config.env` | `[]` |
| `subscription.resources` | Operator resource requests/limits (`spec.config.resources`) | 250m/500Mi → 2/4Gi |
| `operatorImage.enabled` | Patch a custom operator image into the CSV (see below) | `false` |
| `operatorImage.repository` / `tag` | The image to run | `quay.io/ephico2real/namespace-configuration-operator` / `latest` |
| `operatorImage.pullPolicy` | Pull policy written into the CSV | `Always` |
| `operatorImage.expectedImagePattern` | Regex the CSV's current image must match before it is overwritten | upstream `redhat-cop` image |
| `operatorImage.csvDeploymentName` / `containerName` | Where in the CSV to patch (matched by name) | `…-controller-manager` / `manager` |
| `operatorImage.imagePullSecret` | Pull secret for a private registry; empty for public | `""` |
| `operatorImage.reconcile.enabled` | CronJob that re-patches after OLM upgrades revert the CSV | `false` |
| `operatorImage.reconcile.schedule` | Reconcile schedule | `*/10 * * * *` |
| `operatorImage.job.*` | Tool image, wait budget, retries, resources for the Job | see `values.yaml` |
| `podSecurity.audit` / `podSecurity.warn` | PSA labels on the created namespace | `privileged` |

## InstallPlan approval — Manual, without blocking the install

`installPlanApproval: Manual` is the upgrade gate you want, but it also blocks the **first**
install: OLM stages an unapproved InstallPlan and waits for a human, so an unattended
`helm install` never completes.

`subscription.autoApproveInstallPlan` resolves that by approving **only** the InstallPlan for
the pinned `startingCSV`, owned by this chart's Subscription. Everything else is logged and
left alone:

```text
# fresh install — the pinned version installs unattended
match: installplan.../install-vqmz9 installs [namespace-configuration-operator.v1.2.6]
approving installplan.../install-vqmz9
OK: namespace-configuration-operator.v1.2.6 installed via installplan.../install-vqmz9

# a newer version appears in the channel — the gate holds
SKIP installplan.../fake-upgrade-plan: installs [namespace-configuration-operator.v9.9.9],
     which is not the pinned v1.2.6. Left unapproved for a human to review.
```

**The version pin is the approval authority.** To adopt a new version you bump
`subscription.startingCSV` and re-sync — a reviewable change in git — instead of running
`oc patch` against an InstallPlan on the cluster.

Not finding anything to approve is deliberately **not** an error: a staged upgrade nobody has
approved yet is a normal steady state, and failing there would turn every routine
`helm upgrade` red for as long as a newer version sits in the channel.

Set `autoApproveInstallPlan.enabled=false` for a strictly hands-on install; the image-override
hook will then wait for your approval up to its own timeout.

### Why not a Job that flips the Subscription back to Manual?

That also works under plain Helm — a no-op `helm upgrade` does **not** revert the drift,
because Helm 3 only patches fields that differ between the old and new *manifests*. But it
leaves `values.yaml` saying `Automatic` while the cluster says `Manual`, and this chart is
ArgoCD-annotated (`sync-wave` on every template). ArgoCD enforces declared state, so that
mismatch becomes permanent `OutOfSync` and self-heal reverts it. Approving the pinned
InstallPlan keeps declared and live state identical.

### Hook re-runnability

Both hook Jobs carry **two** delete policies, and both are required:

| Annotation | Needed for |
|---|---|
| `helm.sh/hook-delete-policy: before-hook-creation` | `helm upgrade` |
| `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` | ArgoCD sync |

A Job's `spec.template` is **immutable**. Without a delete policy the completed Job survives,
and the next sync tries to create a Job that already exists — failing with *"field is
immutable"*. `BeforeHookCreation` (rather than `HookSucceeded`) deletes the *previous* run at
the start of the next one, so the last run's logs stay available for `oc logs` in between.
`ttlSecondsAfterFinished` is a separate, Kubernetes-level backstop that reaps the Job an hour
after it finishes.

## Operator image override — patching the CSV (Kyverno not required)

Running our **custom-built** operator image no longer needs Kyverno. Enable
`operatorImage.enabled=true` and the chart runs a Job that patches the image directly into the
installed ClusterServiceVersion. Full write-up, including the negative results:
[`../docs/local-testing/LOCAL_TEST_operator_image_override.md`](../docs/local-testing/LOCAL_TEST_operator_image_override.md).

What does **not** work (all tested on-cluster):

- ❌ `Subscription.spec.config` has no `image` field.
- ❌ `RELATED_IMAGE_MANAGER` (env) does **not** change *this* operator's own image — it's an
  operand-image hint, and NCO deploys no operand pods. The env was injected but the manager
  image stayed upstream.
- ❌ IDMS/ITMS only redirect *same-digest* mirrors; our image is a different-digest rebuild.

What **does** work:

- ✅ **Patching the installed CSV.** OLM treats `spec.install.spec.deployments[]` in the CSV as
  the source of truth for the operator Deployment. Patching the `manager` container image there
  made OLM re-apply the Deployment **within 10s**, and the pod came up on our image
  (`imageID` digest verified against the registry). The patch was **not** reverted by OLM.
- ✅ `spec.config` still owns the ZAP log env and `resources`.

```bash
helm upgrade --install nco ./chart \
  --set operatorImage.enabled=true \
  --set operatorImage.repository=quay.io/ephico2real/namespace-configuration-operator \
  --set operatorImage.tag=latest
```

### How the Job behaves

It resolves the CSV from `Subscription.status.installedCSV` (so a version bump is followed
automatically), then locates the deployment and container **by name** — array indices are
discovered at runtime, because in v1.2.6 the manager is `containers[1]` and `kube-rbac-proxy`
is `containers[0]`, which is a bundle detail rather than a contract.

| Situation | Behaviour |
|---|---|
| CSV already holds the target image | Logs `already at target image; skipping patch`, exits 0. No operator restart. |
| CSV holds the expected upstream image | Patches, waits for OLM to propagate, waits for rollout. |
| CSV holds our repo at a different tag | In policy — patches (a tag bump is expected). |
| CSV holds some **other** image | **Refuses** and fails, leaving the CSV untouched. |
| New image never becomes ready | **Rolls back** the CSV *and* the Deployment, then fails. |

The refusal guard is `operatorImage.expectedImagePattern`; widen it if you fork from a
different upstream.

### Two things to know before enabling this

**1. It is one-shot, not enforcing.** Kyverno mutated at admission, so it self-healed. This Job
patches once. An OLM operator upgrade installs a fresh CSV from the catalog and the upstream
image returns. Set `operatorImage.reconcile.enabled=true` for a CronJob that restores it.

**2. A bad image wedges OLM.** If the target image is unpullable, the rollout never completes
and OLM parks the CSV in `InstallWaiting`, where it **stops re-applying the Deployment**.
Reverting only the CSV does *not* recover it — verified on-cluster. That is why the Job's
rollback patches the Deployment directly as well as the CSV. To recover by hand:

```bash
oc set image deploy/namespace-configuration-operator-controller-manager \
  -n namespace-configuration-operator manager=<last-known-good-image>
```
