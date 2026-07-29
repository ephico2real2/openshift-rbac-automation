# Namespace Configuration Operator — install chart

Installs the [Red Hat CoP Namespace Configuration Operator](https://github.com/redhat-cop/namespace-configuration-operator)
(NCO) on OpenShift via OLM. Scope is the **operator install only** — a namespace, an
AllNamespaces OperatorGroup, and a Subscription. The RBAC policies (`GroupConfig` /
`NamespaceConfig` custom resources) live in [`../policies`](../policies) and are applied
separately (they use the operator's own Go templating, so they are intentionally not
Helm-templated).

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
| `subscription.startingCSV` | Pin the initial CSV (empty = channel head) | `namespace-configuration-operator.v1.2.6` |
| `subscription.zapLogLevel` | Operator log verbosity (`ZAP_LOG_LEVEL`) | `info` |
| `subscription.zapDevel` | Development-mode logging (`ZAP_DEVEL`) | `"false"` |
| `subscription.relatedImageManager` | `RELATED_IMAGE_MANAGER` env — does NOT override this operator's image (tested); off by default | `""` |
| `subscription.extraEnv` | Extra env appended to `spec.config.env` | `[]` |
| `subscription.resources` | Operator resource requests/limits (`spec.config.resources`) | 250m/500Mi → 2/4Gi |
| `podSecurity.audit` / `podSecurity.warn` | PSA labels on the created namespace | `privileged` |

## Operator image — Kyverno is required (tested)

Running our **custom-built** operator image still requires the Kyverno mutation. We tested
whether OLM could do it natively and it **cannot** — see the full write-up in
[`../docs/local-testing/LOCAL_TEST_operator_image_override.md`](../docs/local-testing/LOCAL_TEST_operator_image_override.md).

- ❌ `Subscription.spec.config` has no `image` field.
- ❌ `RELATED_IMAGE_MANAGER` (env) does **not** change *this* operator's own image — it's an
  operand-image hint, and NCO deploys no operand pods. In testing the env was injected but
  the manager image stayed upstream.
- ❌ IDMS/ITMS only redirect *same-digest* mirrors; our image is a different-digest rebuild.
- ✅ **What OLM `spec.config` CAN own:** the ZAP log env (`zapLogLevel` / `zapDevel`) and
  `resources`. So the chart can replace the log-level Kyverno policy, but not the image one.

The only Kyverno-free alternative for the image would be a **custom CatalogSource** whose CSV
points at our image (bigger effort, not done here). `subscription.relatedImageManager` is kept
as a configurable env but is **empty by default** and does not override the image.
