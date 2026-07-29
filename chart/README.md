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
| `subscription.relatedImageManager` | Native operator image override (`RELATED_IMAGE_MANAGER`); empty = upstream | `quay.io/ephico2real/namespace-configuration-operator:latest` |
| `subscription.extraEnv` | Extra env appended to `spec.config.env` | `[]` |
| `subscription.resources` | Operator resource requests/limits (`spec.config.resources`) | 250m/500Mi → 2/4Gi |
| `podSecurity.audit` / `podSecurity.warn` | PSA labels on the created namespace | `privileged` |

## Operator image — native override (no Kyverno)

Run a **custom-built** operator image the supported, OLM-owned way via
`subscription.relatedImageManager`. The operator (operator-sdk based) reads the
`RELATED_IMAGE_MANAGER` env var to set its manager image; this chart injects it through
`Subscription.spec.config.env`, so OLM owns the change and it survives reconcile/restart —
**no Kyverno mutation and no IDMS/mirror required.**

```yaml
subscription:
  relatedImageManager: "quay.io/ephico2real/namespace-configuration-operator:latest"
```

Set it to `""` to keep the upstream image referenced by the CSV.

Why this works: OLM's `Subscription.spec.config` has no raw container `image:` field, but
it **does** support `env` — and `RELATED_IMAGE_MANAGER` is the operator's own image-override
hook. So the image change goes in natively through supported config. If you previously
swapped the image with a Kyverno mutation, you can remove it once `relatedImageManager` is
set and the operator redeploys with your image.
