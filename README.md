# OpenShift RBAC Automation

Enterprise-grade RBAC automation for OpenShift using Red Hat Community of Practice (CoP) Namespace Configuration Operator with optional Kyverno validation.

## 🎯 Overview

This solution provides **automated RBAC management** for OpenShift clusters using:
- **Mnemonic-based namespace labeling** (`company.net/mnemonic`)
- **Environment-aware access control** (`company.net/app-environment`)  
- **Automatic RoleBinding & ClusterRoleBinding creation**
- **Production security restrictions** (no admin/edit access in prod)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RBAC Automation Stack                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Group Sync Operator          Red Hat CoP Operator         │
│  ┌─────────────────┐         ┌─────────────────────────┐   │
│  │ Creates Groups: │   ───►  │ Generates RBAC:         │   │
│  │                 │         │                         │   │
│  │ • app-ocp-rbac- │         │ • RoleBindings          │   │
│  │   {mnemonic}-   │         │ • ClusterRoleBindings   │   │
│  │   ns-admin      │         │ • Environment-aware     │   │
│  │ • app-ocp-rbac- │         │ • Pattern-based         │   │
│  │   {mnemonic}-   │         │                         │   │
│  │   cluster-admin │         │                         │   │
│  └─────────────────┘         └─────────────────────────┘   │
│                                                             │
│                    Optional: Kyverno                       │
│                  ┌─────────────────────────┐               │
│                  │ Validates:              │               │
│                  │ • Group naming patterns │               │
│                  │ • Label formats         │               │
│                  │ • Compliance standards  │               │
│                  └─────────────────────────┘               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 🔒 Security Model (example)

> **This role map is a demonstration, not a production standard.** The reusable part of this
> repo is the *mechanism* — the group-name patterns, how a matched group is assigned a role,
> and how namespace labels drive environment-aware behaviour. **Which access level production
> should actually grant is a company policy decision.** Change it in `charts/openshift-rbac-automation/values.yaml` — the roles
> each policy grants are values, not template edits. The manifests in `working-sessions/policies/` are
> design references for reviewing the intent, not the thing to edit to change behaviour. The table below
> records what these example policies currently do.

| Environment | Admin Access | Developer Access | Audit Access |
|-------------|--------------|------------------|--------------|
| **rnd**     | ❌ No        | ✅ Yes           | ✅ Yes       |
| **eng**     | ❌ No        | ✅ Yes           | ✅ Yes       |
| **qa**      | ❌ No        | ✅ Yes           | ✅ Yes       |
| **uat**     | ❌ No        | ✅ Yes           | ✅ Yes       |
| **prod**    | ❌ **No**    | ❌ **No**        | ✅ Yes       |
| **other**   | ❌ **No**    | ❌ **No**        | ❌ **No**    |

**As configured in this example** (`namespaceConfigPolicy.baseline.policies` in values.yaml):
- **Admin access**: not granted by the namespace baseline; cluster-wide admin is `clusterRbac`
- **Developer access** (`edit`): non-production environments only
- **Audit access** (`view`): non-production and prod; an environment not on the allow-list gets nothing

Production is already read-only here. Loosening it means adding a role entry to
`namespaceConfigPolicy.baseline.policies.prod.roles` in `charts/openshift-rbac-automation/values.yaml`; tightening
nonprod means removing one. Prod is a SHORTER LIST than nonprod, not a different structure, which is why
both policies render from one template and differ only in data. The environment values themselves
(`rnd`/`eng`/`qa`/`uat`/`prod`) are just label values the selectors match — equally yours to change.

## 🚀 Quick Start

### 0. Install from the Helm repository (once published)

The chart is published to GitHub Pages by `.github/workflows/helm.yaml`, the same way the
[group-sync-operator chart](https://github.com/ephico2real2/group-sync-operator-helm-chart) and
[group-sync-dashboard](https://github.com/ephico2real2/group-sync-dashboard) are:

```bash
helm repo add openshift-rbac-automation https://ephico2real2.github.io/openshift-rbac-automation
helm repo update
helm search repo openshift-rbac-automation
helm install nco openshift-rbac-automation/openshift-rbac-automation --namespace namespace-configuration-operator
```

Or clone and install from the directory, which is what the rest of this Quick Start does.

### 1. Install Red Hat CoP Namespace Configuration Operator

Use the Helm chart in [`charts/openshift-rbac-automation/`](charts/openshift-rbac-automation/README.md) — it creates an
AllNamespaces OperatorGroup and the Subscription (and the install namespace with `--set createNamespace=true`; the
stock values expect it to exist), and runs a custom operator build by default:

```bash
helm install nco ./charts/openshift-rbac-automation --namespace namespace-configuration-operator
```

See [`charts/openshift-rbac-automation/README.md`](charts/openshift-rbac-automation/README.md) for the options (image override, InstallPlan
approval, resource sizing).

> **Do not install with a hand-applied Subscription into `openshift-marketplace`.** That
> namespace has no OperatorGroup, so the CSV lands in `Failed / NoOperatorGroup` and the
> operator never runs. Earlier revisions of this README recommended exactly that; if you
> followed them, check for an orphaned CSV:
>
> ```bash
> oc get csv -n openshift-marketplace | grep namespace-configuration-operator
> ```

### 2. Deploy RBAC Automation

**Via the chart — every policy is a flag. The baseline NamespaceConfigs and the cluster GroupConfig default
on; the oud-group example and the custom GroupConfig default off.** Do NOT `oc apply` the
manifests under `working-sessions/policies/`: those are **design references**, kept readable so the
intent of each policy can be reviewed. The chart is what deploys.

Just the baseline every team receives (nonprod + prod), per namespace:

```bash
helm upgrade --install nco charts/openshift-rbac-automation -n namespace-configuration-operator \
  --set namespaceConfigPolicy.enabled=true \
  --set namespaceConfigPolicy.baseline.enabled=true
```

Or everything, which is one command rather than four — **separate upgrades that supply values are not
cumulative by default.** An upgrade with at least one `-f` / `--set` argument and without `--reuse-values`
or `--reset-then-reuse-values` starts from the chart defaults and applies that invocation's arguments, so an
override you leave off returns to its default; for the off-by-default oud-group and custom policies that
switches the policy **off**, and switching a policy off revokes what it created. (With no value arguments
and without `--reset-values`, Helm keeps the previous release's values; `--reuse-values` merges them with
new arguments; `--reset-values` discards them and wins if both flags are given. See `helm upgrade --help`.)

```bash
helm upgrade --install nco charts/openshift-rbac-automation -n namespace-configuration-operator \
  --set namespaceConfigPolicy.enabled=true \
  --set namespaceConfigPolicy.baseline.enabled=true \
  --set clusterRbac.enabled=true \
  --set namespaceConfigPolicy.oudGroup.enabled=true \
  --set namespaceConfigPolicy.oudGroup.policies.bdp.enabled=true \
  --set customGroupConfig.enabled=true
```

For anything beyond a quick test, put the flags in a values file and use `-f` — that way the enabled
set is reviewable in git instead of living in someone's shell history.

`customGroupConfig` binds ClusterRoles the chart does **not** create. Apply the role first, or the
binding is created, reports healthy and grants nothing:

```bash
oc apply -f working-sessions/policies/database-admin-clusterrole.yaml
```

Optional standards validation (Kyverno, Audit mode — reports, does not block):

```bash
oc apply -f working-sessions/policies/kyverno-validation-only.yaml
```

Optional guardrail on who may write the operator's CRs (Kyverno `ValidatingPolicy`, ships in Audit).
Measured on the sandbox cluster (the table is in the policy's header): OLM aggregates the CRDs into
the cluster-wide `admin` and `edit` roles, so the chart's `-cluster-developer` tier can create a
NamespaceConfig that binds any ClusterRole anywhere. The policy allows only cluster administrators (by
name and group, otherwise by a wildcard SubjectAccessReview), groups named `app-ocp-rbac-*-cluster-admin`,
the operator's service account and the GitOps controller; the header of the file says why each one.
`working-sessions/scripts/verify-nco-writer-policy.sh` proves it with impersonated `--dry-run=server`
writes, because `oc auth can-i` stops at authorization and never sees admission:

The same tiers hold `edit` on the `kyverno` namespace and Kyverno exempts its own configuration from its own
policies, so a companion `ValidatingAdmissionPolicy` (the API server's admission) keeps that configuration to
cluster administrators; apply it first, or the guardrail can be switched off by the people it restricts.

```bash
oc apply -f working-sessions/policies/vap-protect-kyverno-configuration.yaml
oc apply -f working-sessions/policies/kyverno-restrict-nco-writers.yaml
working-sessions/scripts/verify-nco-writer-policy.sh
```

Moving any of the Kyverno policies from Audit to Deny is a one-field change in the file it already lives in, with
preconditions and a verification step: `working-sessions/docs/kyverno-audit-to-deny.md`.

### 3. Test with a Namespace

```bash
# Create development namespace
oc new-project payment-dev
oc label namespace payment-dev \
  company.net/mnemonic=paym \
  company.net/app-environment=rnd

# Verify RoleBindings created
oc get rolebindings -n payment-dev
# Expected: paym-developer-rb, paym-audit-rb  (no paym-admin-rb: the baseline grants no admin)
```

### 4. Test Production Restrictions

```bash
# Create production namespace
oc new-project payment-prod
oc label namespace payment-prod \
  company.net/mnemonic=paym \
  company.net/app-environment=prod

# Verify prod is audit-only
oc get rolebindings -n payment-prod
# Expected: paym-audit-rb (view) only — no admin, no developer
```

> In this example prod is audit-only.
> **That split is a company policy decision, not a rule** — adjust
> `namespaceConfigPolicy.baseline.policies.prod.roles` in `charts/openshift-rbac-automation/values.yaml` to match your own. See
> [architecture.md](working-sessions/docs/architecture.md).

### 5. Verify System Access

```bash
# The chart deploys no user-workload-monitoring policy: the former reference policy is parked under
# working-sessions/policies/ and is not chart output, so nothing is expected in that namespace.

# Check infrastructure team access (if configured)
oc get clusterrolebindings | grep platform
```

## ✅ Verification Commands

### Verify All Deployed Configurations

```bash
# List all NamespaceConfigs, GroupConfigs, and UserConfigs
oc get namespaceconfig,groupconfig,userconfig
```

### Verify Non-Production Namespace RBAC

```bash
# Check RoleBindings in a non-prod namespace (should have 2: developer and audit; the baseline grants no admin)
oc get rolebindings -n beta-rnd -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected output:
# NAME                ROLE                AGE
# beta-audit-rb       ClusterRole/view    XXm
# beta-developer-rb   ClusterRole/edit    XXm
```

**Show RoleBindings with Group Names:**

```bash
# Option 1: Using custom-columns (works everywhere, no jq required)
oc get rolebindings -n beta-rnd \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator \
  -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,GROUP:.subjects[0].name'

# Expected output:
# NAME                ROLE    GROUP
# beta-audit-rb       view    app-ocp-rbac-beta-ns-audit
# beta-developer-rb   edit    app-ocp-rbac-beta-ns-developer
```

```bash
# Option 2: Pretty formatted with jq (includes creation timestamp)
oc get rolebindings -n beta-rnd \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator -o json | \
  jq -r '.items[] | "\(.metadata.name)\t| Group: \(.subjects[0].name)\t| Role: \(.roleRef.name)\t| Created: \(.metadata.creationTimestamp)"' | \
  column -t -s $'\t'

# Expected output:
# beta-audit-rb      | Group: app-ocp-rbac-beta-ns-audit      | Role: view   | Created: 2026-03-16T23:50:22Z
# beta-developer-rb  | Group: app-ocp-rbac-beta-ns-developer  | Role: edit   | Created: 2026-03-16T23:50:22Z
```

```bash
# Option 3: Table format with headers (cleanest output)
oc get rolebindings -n beta-rnd \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator -o json | \
  jq -r '["NAME","GROUP","ROLE","CREATED"], (.items[] | [.metadata.name, .subjects[0].name, .roleRef.name, .metadata.creationTimestamp]) | @tsv' | \
  column -t -s $'\t'

# Expected output:
# NAME               GROUP                           ROLE   CREATED
# beta-audit-rb      app-ocp-rbac-beta-ns-audit      view   2026-03-16T23:50:22Z
# beta-developer-rb  app-ocp-rbac-beta-ns-developer  edit   2026-03-16T23:50:22Z
```

### Verify Production Namespace RBAC

```bash
# Check RoleBindings in a prod namespace (should have 1: audit - prod is read-only)
oc get rolebindings -n beta-prod -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected output:
# NAME                ROLE               AGE
# beta-audit-rb       ClusterRole/view   XXd
# (no admin-rb and no developer-rb - this is correct for production)
```

### Verify Cluster-Level RBAC

```bash
# List all managed ClusterRoleBindings
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check specific cluster group types
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-admin
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-developer
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-audit

# By the role ACTUALLY BOUND, which is the effective-permission question and spans both scopes.
# role-type is the tier we promised; bound-role is the ClusterRole that tier resolves to — and the
# words differ on purpose (cluster-audit binds view, cluster-developer binds edit).
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/bound-role=view
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/bound-role=admin

# Everything granted to one group, across every policy
oc get rolebinding,clusterrolebinding -A -l rbac.ocp.io/group-name=app-ocp-rbac-beta-ns-admin

# Every cluster-wide grant — the blast-radius question
oc get clusterrolebinding -l rbac.ocp.io/scope=cluster-wide
```

**Show ClusterRoleBindings with Group Names:**

```bash
# Option 1: All managed ClusterRoleBindings with groups (custom-columns)
oc get clusterrolebindings \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator \
  -o custom-columns='NAME:.metadata.name,CLUSTERROLE:.roleRef.name,GROUP:.subjects[0].name'

# Expected output:
# NAME                                          CLUSTERROLE   GROUP
# app-ocp-rbac-alpha-cluster-admin-crb          admin         app-ocp-rbac-alpha-cluster-admin
# app-ocp-rbac-alpha-cluster-audit-crb          view          app-ocp-rbac-alpha-cluster-audit
# app-ocp-rbac-alpha-cluster-developer-crb      edit          app-ocp-rbac-alpha-cluster-developer
# ...
```

```bash
# Option 2a: Show ALL cluster role types at once (admin, developer, audit)
oc get clusterrolebindings \
  -l 'rbac.ocp.io/role-type' \
  -o custom-columns='NAME:.metadata.name,ROLE-TYPE:.metadata.labels.rbac\.ocp\.io/role-type,CLUSTERROLE:.roleRef.name,GROUP:.subjects[0].name' | \
  grep -E "^(NAME|.*cluster-)"

# Expected output:
# NAME                                          ROLE-TYPE           CLUSTERROLE   GROUP
# app-ocp-rbac-alpha-cluster-admin-crb          cluster-admin       admin         app-ocp-rbac-alpha-cluster-admin
# app-ocp-rbac-alpha-cluster-audit-crb          cluster-audit       view          app-ocp-rbac-alpha-cluster-audit
# app-ocp-rbac-alpha-cluster-developer-crb      cluster-developer   edit          app-ocp-rbac-alpha-cluster-developer
# app-ocp-rbac-demo-cluster-admin-crb           cluster-admin       admin         app-ocp-rbac-demo-cluster-admin
# ...
```

```bash
# Option 2b: Filter by specific role type

# Cluster-admin groups only
oc get clusterrolebindings \
  -l rbac.ocp.io/role-type=cluster-admin \
  -o custom-columns='NAME:.metadata.name,CLUSTERROLE:.roleRef.name,GROUP:.subjects[0].name'

# Expected output:
# NAME                                      CLUSTERROLE   GROUP
# app-ocp-rbac-alpha-cluster-admin-crb      admin         app-ocp-rbac-alpha-cluster-admin
# app-ocp-rbac-demo-cluster-admin-crb       admin         app-ocp-rbac-demo-cluster-admin
# app-ocp-rbac-platform-cluster-admin-crb   admin         app-ocp-rbac-platform-cluster-admin

# Cluster-developer groups
oc get clusterrolebindings \
  -l rbac.ocp.io/role-type=cluster-developer \
  -o custom-columns='NAME:.metadata.name,CLUSTERROLE:.roleRef.name,GROUP:.subjects[0].name'

# Expected output:
# NAME                                          CLUSTERROLE   GROUP
# app-ocp-rbac-alpha-cluster-developer-crb      edit          app-ocp-rbac-alpha-cluster-developer
# app-ocp-rbac-demo-cluster-developer-crb       edit          app-ocp-rbac-demo-cluster-developer
# app-ocp-rbac-finance-cluster-developer-crb    edit          app-ocp-rbac-finance-cluster-developer

# Cluster-audit groups
oc get clusterrolebindings \
  -l rbac.ocp.io/role-type=cluster-audit \
  -o custom-columns='NAME:.metadata.name,CLUSTERROLE:.roleRef.name,GROUP:.subjects[0].name'

# Expected output:
# NAME                                      CLUSTERROLE   GROUP
# app-ocp-rbac-alpha-cluster-audit-crb      view          app-ocp-rbac-alpha-cluster-audit
# app-ocp-rbac-demo-cluster-audit-crb       view          app-ocp-rbac-demo-cluster-audit
```

```bash
# Option 3: Pretty formatted with jq
oc get clusterrolebindings \
  -l rbac.ocp.io/role-type=cluster-admin -o json | \
  jq -r '.items[] | "\(.metadata.name)\t| ClusterRole: \(.roleRef.name)\t| Group: \(.subjects[0].name)"' | \
  column -t -s $'\t'

# Expected output:
# app-ocp-rbac-alpha-cluster-admin-crb     | ClusterRole: admin  | Group: app-ocp-rbac-alpha-cluster-admin
# app-ocp-rbac-demo-cluster-admin-crb      | ClusterRole: admin  | Group: app-ocp-rbac-demo-cluster-admin
# app-ocp-rbac-platform-cluster-admin-crb  | ClusterRole: admin  | Group: app-ocp-rbac-platform-cluster-admin
```

### Verify Groups

```bash
# List all namespace-level groups
oc get groups | grep "ns-admin\|ns-developer\|ns-audit"

# List all cluster-level groups
oc get groups | grep "cluster-admin\|cluster-developer\|cluster-audit"
```

### Verify Monitoring Access

```bash
# The chart currently deploys no user-workload-monitoring policy. The former reference policy is parked under
# working-sessions/policies/ and must not be read as chart output:
oc get rolebindings -n openshift-user-workload-monitoring -l app.kubernetes.io/managed-by=namespace-configuration-operator
# Expected: No resources found
```

## 📁 Repository Structure

```
├── README.md                                     # This file
├── .github/workflows/
│   ├── ci.yaml                                   # lint + render checks, on every PR
│   └── helm.yaml                                 # publishes the chart to gh-pages
├── charts/                                       # chart-releaser packages every subdirectory here
│   └── openshift-rbac-automation/                # the chart: operator install AND the policies
│       ├── Chart.yaml
│       ├── values.yaml                           # Every policy flag; baseline namespace + cluster tiers default on
│       └── templates/
│           ├── 00-namespace.yaml … 09-…-job.yaml # Operator install: OLM, image override, InstallPlan
│           ├── _helpers.tpl                      # Shared label block (nco.labels)
│           └── rbac-policies/                    # ← THE POLICIES. Edit here, not above.
│               ├── _README.txt                   # What each one grants, and the rules for editing
│               ├── 10-baseline-namespaceconfig-rbac.yaml   # nonprod + prod, per namespace
│               ├── 11-baseline-groupconfig-rbac.yaml       # cluster-wide tiers
│               ├── 12-custom-oud-group-namespaceconfig-rbac.yaml  # bespoke submitter Role
│               └── 13-custom-groupconfig-rbac.yaml         # ClusterRoles we define
└── working-sessions/                             # Reference material and hand-applied manifests
    ├── README.md                                 # Operator behaviour, and the GOTCHAs — read this
    ├── policies/                                  # DESIGN REFERENCES — read these, do not apply them.
    │                                              #   The chart deploys the equivalents. Exceptions:
    │                                              #   database-admin-clusterrole.yaml (a supporting
    │                                              #   ClusterRole the chart binds but cannot create)
    │                                              #   and the kyverno-*.yaml validation policies.
    ├── scripts/                                  # Operational helpers (see scripts/README.md)
    └── docs/
        ├── labels-and-annotations.md             # THE label/annotation contract
        ├── templating-guide.md                   # How the templates work, $group, Helm functions
        ├── architecture.md                       # Policy behaviour, access matrix, security model
        ├── redhat-cop-rbac-deployment-guide.md
        ├── rbac-verification-guide.md
        ├── scaling-system-namespace-access.md
        ├── groups-and-bindings-examples.md
        ├── known-issues.md
        ├── examples/                             # GroupSync CR, CRD-access example
        ├── local-testing/                        # Image-override findings, Kyverno backups
        └── planning/                             # Completed design notes
```

**The policies ship as part of the chart, each behind its own flag: the baseline NamespaceConfigs and the
cluster GroupConfig default on, the oud-group example and the custom GroupConfig default off.**

`working-sessions/policies/` holds **manual manifests kept for design purposes** — the readable
statement of what each policy is meant to do, reviewed as YAML rather than as a template. They are not
the deployment path and applying them would duplicate what the chart creates. Their labels are held to
the same contract as the chart's output so the two can be compared line for line.

Two deliberate exceptions are genuinely applied: `database-admin-clusterrole.yaml`, a supporting
ClusterRole the chart binds but does not create, and the `kyverno-*.yaml` validation policies.

## 🎯 Key Features

### ✅ **Environment-Aware Security**
- **Explicit allowlist approach**: Only `rnd`, `eng`, `qa`, `uat` get developer (`edit`) and audit (`view`) access
- **Production restrictions**: No admin/edit access in `prod`
- **Unknown environment protection**: Unrecognized environments receive no baseline RBAC grant (the selector is an `In` allow-list)
- **Typo protection**: Misspelled environments (e.g., `production`) are denied access

### ✅ **Mnemonic-Driven Automation**
- Uses existing `company.net/mnemonic` labels
- 4-letter mnemonic format (e.g., `paym`, `frnt`, `back`)
- Automatic group name resolution

### ✅ **Pattern-Based Group Matching**
- Works with Group Sync Operator naming patterns
- Supports: `app-ocp-rbac-{mnemonic}-(ns|cluster)-(admin|developer|audit)`
- No manual group labeling required

### ✅ **Team-Friendly Operation**
- Simple namespace labeling workflow
- Automatic RBAC creation and cleanup
- Rich metadata for monitoring and troubleshooting

### ✅ **System Namespace Access**
- **Monitoring access**: not deployed by the chart; the former reference policy is parked under `working-sessions/policies/` and is not chart output
- **Dedicated infrastructure groups**: the platform tiers are `clusterRbac` (admin / edit / view ClusterRoleBindings), not a monitoring RoleBinding

## 🔧 Custom Domain Support

If you need a different domain instead of `company.net`, override the selector keys in the chart values;
the templates render the new keys directly, so a chart install needs no generated copies. (A legacy helper,
`working-sessions/scripts/create-custom-domain-configs.sh`, rewrites only the parked reference manifests and
is not the chart deployment path.)

```yaml
namespaceConfigPolicy:
  baseline:
    mnemonicLabelKey: test.example.com/mnemonic
    environmentLabelKey: test.example.com/app-environment
  oudGroup:
    policies:
      bdp:
        labelKey: test.example.com/oud-group
```

**Note:** Make sure to label your namespaces with the new domain:
```bash
oc label namespace <namespace-name> \
  test.example.com/mnemonic=<mnemonic> \
  test.example.com/app-environment=<environment>
```

## 📚 Documentation

Start here if you are changing a policy:

- **[Labels and annotations — the contract](working-sessions/docs/labels-and-annotations.md)** — every
  label and annotation this project sets, what each answers, and a query cookbook. If a key is not in
  there, we do not set it.
- **[Templating guide](working-sessions/docs/templating-guide.md)** — how the templates compute their
  values: the two template engines, the three ways `$group` is derived, every Helm function in use, and
  the traps. Read before editing `charts/openshift-rbac-automation/templates/rbac-policies/`.
- **[charts/openshift-rbac-automation/templates/rbac-policies/_README.txt](charts/openshift-rbac-automation/templates/rbac-policies/_README.txt)** — what each
  of the four policies grants, and the rules for adding one.

Background and operations:

- **[Operator behaviour and GOTCHAs](working-sessions/README.md)** — the measured behaviour of the
  Namespace Configuration Operator, including that deleting a policy CR **revokes what it created**
- **[Architecture](working-sessions/docs/architecture.md)** — what each policy does, access matrix, security model
- **[Deployment Guide](working-sessions/docs/redhat-cop-rbac-deployment-guide.md)** — installation and testing
- **[Verification Guide](working-sessions/docs/rbac-verification-guide.md)** — verification commands and expected output
- **[Scaling Guide](working-sessions/docs/scaling-system-namespace-access.md)** — adding new system namespace access
- **[Groups and Bindings Examples](working-sessions/docs/groups-and-bindings-examples.md)** — groups, RoleBindings, ClusterRoleBindings
- **[Known Issues](working-sessions/docs/known-issues.md)** — operator bugs hit during rollout and how they were resolved
- **[Local Testing](working-sessions/docs/local-testing/LOCAL_TEST_operator_image_override.md)** — operator image override findings on CRC

## ⚠️ Important: GroupConfig Selector Filtering

**Issue**: GroupConfig with empty `labelSelector: {}` processes ALL groups and creates ClusterRoleBindings for namespace-level groups.

**Problem**: 
```yaml
# ❌ WRONG - Creates ClusterRoleBindings for both cluster AND namespace groups
labelSelector: {}
```

**Solution**: Use targeted selector + template filtering:
```yaml
# ✅ CORRECT - Only LDAP-synced groups + template filtering
labelSelector:
  matchExpressions:
  - key: group-sync-operator.redhat-cop.io/sync-provider
    operator: Exists
templates:
  - objectTemplate: |
      {{- if and (contains "app-ocp-rbac-" .Name) (contains "-cluster-" .Name) }}
      # ClusterRoleBinding YAML here
      {{- end }}
```

**Why this works**:
1. **labelSelector**: Only processes LDAP-synced groups (excludes manual groups)
2. **Template conditional**: Only creates ClusterRoleBindings for cluster-level groups
3. **Result**: `app-ocp-rbac-*-ns-*` groups are processed but filtered out

**Expected behavior**: a namespace-level group renders an empty document and creates nothing; that silence is the filter working, not an error.

## 🎯 Advanced: Modular GroupConfig Pattern

> **Illustrative only, not chart output.** The snippets below show the pattern for a GroupConfig you would
> add to values (or park under `working-sessions/policies/`). The repository ships no
> `security-admin-rbac.yaml`, `monitoring-rbac.yaml` or `backup-operator-rbac.yaml`, and the `kubectl apply`
> lines are not install steps.

**Benefit**: This architecture makes it incredibly easy to create **custom ClusterRole assignments for specific group patterns**.

### Creating Custom Role Assignments

Instead of complex multi-template files, create focused single-purpose GroupConfigs:

```yaml
# database-admin-rbac.yaml
apiVersion: redhatcop.redhat.io/v1alpha1
kind: GroupConfig
metadata:
  name: database-admin-rbac
spec:
  labelSelector:
    matchExpressions:
    - key: group-sync-operator.redhat-cop.io/sync-provider
      operator: In
      values:
      - clusterrole-ldap-groupsync_ldap
  templates:
    - objectTemplate: |
        {{- if hasSuffix "-database-admin" .Name }}
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: "{{ .Name }}-crb"
        subjects:
        - kind: Group
          name: "{{ .Name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          kind: ClusterRole
          name: database-admin  # Custom ClusterRole
        {{- end }}
```

### Pattern Benefits

1. **🎯 Flexible Targeting**: Each file targets different regex patterns
2. **🔧 Custom Roles**: Easy to assign any ClusterRole (built-in or custom)
3. **📁 Organized**: One file per role/pattern - easy to find and maintain
4. **⚡ No Conflicts**: Independent files won't interfere with each other
5. **🧪 Easy Testing**: Test each pattern in isolation
6. **📈 Scalable**: Add new patterns without touching existing ones

### Real-World Examples

```bash
# Security teams
kubectl apply -f security-admin-rbac.yaml
# Targets: app-ocp-rbac-*-security-admin → security-reviewer ClusterRole

# Monitoring teams  
kubectl apply -f monitoring-rbac.yaml
# Targets: app-ocp-rbac-*-monitoring → prometheus-admin ClusterRole

# Backup operators
kubectl apply -f backup-operator-rbac.yaml  
# Targets: app-ocp-rbac-*-backup → backup-admin ClusterRole
```

This modular approach transforms complex RBAC management into simple, focused configurations!

## 🔧 Troubleshooting

### Common Issues

**RoleBindings not created:**
```bash
# Check namespace has required labels
oc get namespace <namespace-name> --show-labels

# Verify operator is running
oc get pods -n namespace-configuration-operator
```

**Production has admin access:**
```bash
# Verify environment label is correct
oc get namespace <namespace-name> -o yaml | grep app-environment

# Should be exactly "prod" (not "production")
```

**ClusterRoleBindings not created:**
```bash
# Verify groups exist with correct naming
oc get groups | grep app-ocp-rbac | grep cluster
```

## 🤝 Contributing

1. **Test changes** in non-production environment first
2. **Update documentation** for any configuration changes
3. **Verify** both namespace and cluster RBAC functionality
4. **Check** production security restrictions work correctly

## 📞 Support

- **Issues**: Create GitHub issues for bugs or feature requests
- **Documentation**: All guides in `/docs` directory
- **Validation**: Optional Kyverno policy for standards enforcement

---

**🎉 Your OpenShift RBAC automation is ready for enterprise deployment!**