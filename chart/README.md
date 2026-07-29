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
| `subscription.installPlanApproval` | `Automatic` or `Manual` | `Automatic` |
| `subscription.startingCSV` | Pin the initial CSV (empty = channel head) | `""` |
| `podSecurity.audit` / `podSecurity.warn` | PSA labels on the created namespace | `privileged` |

## Operator image

This chart does **not** set the operator image — OLM installs it from the CSV. If you
need to run a **custom-built** operator image (a different digest than upstream), note:

- **OLM cannot override the image via the Subscription** — `Subscription.spec.config`
  supports `env`/`resources`/`tolerations`/`nodeSelector`/`affinity`/`volumes`/
  `annotations`, but **not** an image field.
- **IDMS / ITMS (image mirror sets) do not apply** — they redirect to a mirror serving
  the *same digest*; they cannot point a digest reference at a different image.
- The supported native path to run your own image is a **custom CatalogSource** (a
  file-based-catalog bundle whose CSV references your image); the Subscription's `source`
  then points at it. Alternatively, an admission mutation (e.g. Kyverno) can swap the
  running Deployment's image — a working stop-gap, but a webhook rather than a native
  OLM redirect.
