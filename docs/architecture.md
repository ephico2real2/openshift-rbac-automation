# RBAC Automation Architecture

How the policies in [`../policies`](../policies) combine into an environment-aware RBAC model
driven by LDAP group names and namespace labels.

For installation see the [root README](../README.md); the operator itself is installed by the
Helm chart in [`../chart`](../chart).

## Core policies

| Policy | Purpose | Groups used | Environment aware |
|---|---|---|---|
| `nonprod-namespaceconfig-rbac.yaml` | Non-prod namespace roles | `ns-(admin\|developer\|audit)` | Yes |
| `prod-namespaceconfig-rbac.yaml` | Production namespace roles | `ns-(developer\|audit)` | Yes |
| `cluster-admin-groupconfig-rbac.yaml` | Cluster admin access | `cluster-admin` | No |
| `cluster-developer-groupconfig-rbac.yaml` | Cluster developer access | `cluster-developer` | No |
| `cluster-audit-groupconfig-rbac.yaml` | Cluster audit access | `cluster-audit` | No |
| `database-admin-groupconfig-rbac.yaml` | Database infrastructure team | `platform-database-admins` | No |
| `user-workload-monitoring-admin-groupconfig-rbac.yaml` | Monitoring system access | `ns-admin` | No |
| `kyverno-validation-only.yaml` | Standards validation (optional) | n/a | No |

## What each policy does

### Standards validation — `kyverno-validation-only.yaml`

Validates group naming (`app-ocp-rbac-{mnemonic}-(ns|cluster)-(admin|developer|audit)`), the
4-lowercase-letter mnemonic format, environment values (`rnd`, `eng`, `qa`, `uat`, `prod`), and
that namespaces carry the required labels. Optional — it enforces conventions, it does not
grant access.

### Non-production namespaces — `nonprod-namespaceconfig-rbac.yaml`

Selects namespaces where `company.net/app-environment` is one of `rnd`, `eng`, `qa`, `uat`, and
creates **three** RoleBindings:

| RoleBinding | ClusterRole | Group |
|---|---|---|
| `{mnemonic}-admin-rb` | `admin` | `app-ocp-rbac-{mnemonic}-ns-admin` |
| `{mnemonic}-developer-rb` | `edit` | `app-ocp-rbac-{mnemonic}-ns-developer` |
| `{mnemonic}-audit-rb` | `view` | `app-ocp-rbac-{mnemonic}-ns-audit` |

### Production namespaces — `prod-namespaceconfig-rbac.yaml`

Selects namespaces where `company.net/app-environment` is `prod` and creates **two**
RoleBindings. Admin is withheld; developer is **not**:

| RoleBinding | ClusterRole | Group |
|---|---|---|
| `{mnemonic}-developer-rb` | `edit` | `app-ocp-rbac-{mnemonic}-ns-developer` |
| `{mnemonic}-audit-rb` | `view` | `app-ocp-rbac-{mnemonic}-ns-audit` |

> **Production is not read-only.** Developers hold `edit` — write access — in production. This
> is deliberate ("power users in prod"), and the policy's own description says so: *"audit/developer
> access for ALL environments (admin restricted to non-prod)"*. What production removes is
> **admin**, not write. Verified on-cluster: a prod namespace carries `{mnemonic}-developer-rb`
> → `ClusterRole/edit` alongside `{mnemonic}-audit-rb` → `ClusterRole/view`.

### Cluster-level access

`cluster-admin-`, `cluster-developer-` and `cluster-audit-groupconfig-rbac.yaml` create
ClusterRoleBindings for `app-ocp-rbac-{mnemonic}-cluster-(admin|developer|audit)` groups. Kept
as three focused files rather than one, so each can be reviewed and rolled out independently.

### Infrastructure teams — `database-admin-groupconfig-rbac.yaml`

Cluster-wide access for the `platform-database-admins` group. No per-namespace setup needed.

### System monitoring — `user-workload-monitoring-admin-groupconfig-rbac.yaml`

Grants `ns-admin` groups monitoring configuration, Prometheus rules and AlertManager routing
access in `openshift-user-workload-monitoring`.

## Access matrix

| Group type | Namespace admin | Namespace developer | Namespace audit | Cluster access | Monitoring config | Prometheus rules | Alert routing |
|---|---|---|---|---|---|---|---|
| `ns-admin` | Non-prod only | Non-prod only | Yes | No | Yes | Yes | Yes |
| `ns-developer` | No | **All environments** | Yes | No | Yes | No | No |
| `ns-audit` | No | No | Yes | No | No | No | No |
| `cluster-admin` | No | No | No | Yes (`admin`) | No | No | No |
| `cluster-developer` | No | No | No | Yes (`edit`) | No | No | No |
| `cluster-audit` | No | No | No | Yes (`view`) | No | No | No |
| dedicated groups | No | No | No | Yes (custom) | No | No | No |

## Security model

| Environment | Admin | Developer | Audit |
|---|---|---|---|
| `rnd` / `eng` / `qa` / `uat` | Yes | Yes | Yes |
| `prod` | **No** | Yes (`edit`) | Yes |
| unlabelled / other | No | No | No |

- **Admin** is restricted to non-production.
- **Developer** (`edit`) applies in every selected environment, production included.
- **Audit** (`view`) is universal.
- A namespace with no `company.net/mnemonic` and `company.net/app-environment` labels matches
  neither selector and gets **no** managed RoleBindings at all.

## Usage

Standard application team — groups `app-ocp-rbac-paym-ns-{admin,developer,audit}`:

```bash
oc new-project payment-dev
oc label namespace payment-dev \
  company.net/mnemonic=paym \
  company.net/app-environment=qa
# Result: paym-admin-rb, paym-developer-rb, paym-audit-rb
```

Infrastructure database team — group `platform-database-admins` needs no namespace setup; the
ClusterRoleBinding is created from the group alone.

## Adding access to a new system namespace

1. Copy an existing system-access policy as a template.
2. Update the name and component labels.
3. Define the target namespace and role templates.
4. `oc apply -f policies/<new-policy>.yaml`

See [`scaling-system-namespace-access.md`](scaling-system-namespace-access.md) for the full
pattern and [`examples/redhat-cop-custom-crd-access.yaml`](examples/redhat-cop-custom-crd-access.yaml)
for a CRD-access template.
