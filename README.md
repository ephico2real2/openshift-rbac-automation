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

## 🔒 Security Model

| Environment | Admin Access | Developer Access | Audit Access |
|-------------|--------------|------------------|--------------|
| **rnd**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **eng**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **qa**      | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **uat**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **prod**    | ❌ **No**    | ✅ Yes           | ✅ Yes       |
| **other**   | ❌ **No**    | ✅ Yes           | ✅ Yes       |

**Security Design**:
- **Admin access**: Restricted to non-production environments only
- **Developer access**: Available in ALL environments (power users in prod)
- **Audit access**: Universal read-only access across all environments

## 🚀 Quick Start

### 1. Install Red Hat CoP Namespace Configuration Operator

```bash
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: namespace-configuration-operator
  namespace: openshift-marketplace
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: namespace-configuration-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 2. Deploy RBAC Automation

```bash
# Deploy core RBAC policies
oc apply -f policies/nonprod-namespaceconfig-rbac.yaml
oc apply -f policies/prod-namespaceconfig-rbac.yaml
oc apply -f policies/cluster-admin-groupconfig-rbac.yaml
oc apply -f policies/cluster-developer-groupconfig-rbac.yaml
oc apply -f policies/cluster-audit-groupconfig-rbac.yaml
oc apply -f policies/database-admin-groupconfig-rbac.yaml
oc apply -f policies/user-workload-monitoring-admin-groupconfig-rbac.yaml

# Optional: Deploy validation
oc apply -f policies/kyverno-validation-only.yaml
```

### 3. Test with a Namespace

```bash
# Create development namespace
oc new-project payment-dev
oc label namespace payment-dev \
  company.net/mnemonic=paym \
  company.net/app-environment=rnd

# Verify RoleBindings created
oc get rolebindings -n payment-dev
# Expected: paym-admin-rb, paym-developer-rb, paym-audit-rb
```

### 4. Test Production Restrictions

```bash
# Create production namespace
oc new-project payment-prod
oc label namespace payment-prod \
  company.net/mnemonic=paym \
  company.net/app-environment=prod

# Verify only audit access
oc get rolebindings -n payment-prod
# Expected: Only paym-audit-rb (no admin/developer access)
```

### 5. Verify System Access

```bash
# Check monitoring access (automatic for all teams)
oc get rolebindings -n openshift-user-workload-monitoring | grep paym
# Expected: monitoring config and prometheus rules access

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
# Check RoleBindings in a non-prod namespace (should have 3: admin, developer, audit)
oc get rolebindings -n beta-rnd -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected output:
# NAME                ROLE                AGE
# beta-admin-rb       ClusterRole/admin   XXm
# beta-audit-rb       ClusterRole/view    XXm
# beta-developer-rb   ClusterRole/edit    XXm
```

### Verify Production Namespace RBAC

```bash
# Check RoleBindings in a prod namespace (should have 2: developer, audit - NO ADMIN)
oc get rolebindings -n beta-prod -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected output:
# NAME                ROLE               AGE
# beta-audit-rb       ClusterRole/view   XXd
# beta-developer-rb   ClusterRole/edit   XXd
# (NO admin-rb - this is correct for production)
```

### Verify Cluster-Level RBAC

```bash
# List all managed ClusterRoleBindings
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check specific cluster group types
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-admin
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-developer
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-audit
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
# Check monitoring RoleBindings created for ns-admin groups
oc get rolebindings -n openshift-user-workload-monitoring -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Should show monitoring-config-edit, prometheus-rules-edit, and alert-routing-edit bindings
```

## 📁 Repository Structure

```
├── README.md                           # This file
├── policies/                           # RBAC automation policies
│   ├── nonprod-namespaceconfig-rbac.yaml    # Non-production namespace RBAC
│   ├── prod-namespaceconfig-rbac.yaml       # Production namespace RBAC
│   ├── cluster-admin-groupconfig-rbac.yaml  # Cluster admin access
│   ├── cluster-developer-groupconfig-rbac.yaml # Cluster developer access
│   ├── cluster-audit-groupconfig-rbac.yaml  # Cluster audit access
│   ├── database-admin-groupconfig-rbac.yaml # Database admin access
│   ├── user-workload-monitoring-admin-groupconfig-rbac.yaml # Monitoring access
│   └── kyverno-validation-only.yaml         # Optional: Standards validation
├── docs/                              # Documentation
│   ├── redhat-cop-rbac-deployment-guide.md  # Complete deployment guide
│   ├── scaling-system-namespace-access.md    # Scaling guide for new systems
│   ├── groups-and-bindings-examples.md       # Groups and bindings examples with commands
│   └── examples/                              # Example templates
│       └── redhat-cop-custom-crd-access.yaml     # CRD access template
└── scripts/                          # Automation scripts
    └── setup-test-namespaces.sh      # Test namespace creation
```

## 🎯 Key Features

### ✅ **Environment-Aware Security**
- **Explicit allowlist approach**: Only `rnd`, `eng`, `qa`, `uat` get admin/edit access
- **Production restrictions**: No admin/edit access in `prod`
- **Unknown environment protection**: Unrecognized environments default to audit-only
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
- **Monitoring access**: Automatic user workload monitoring configuration and alerting
- **Uses standard groups**: Works with existing `app-ocp-rbac-{mnemonic}-ns-(admin|developer)` groups
- **Dedicated infrastructure groups**: Platform teams with specialized cluster-wide access
- **Scalable pattern**: Easy to add new system namespace access
- **Environment aware**: Monitoring access available in all environments

## 🔧 Custom Domain Support

If you need to use a different domain instead of `company.net`, you can generate custom versions of the NamespaceConfig files:

```bash
# Generate configs for a custom domain
cd <path-to-repo>/openshift-rbac-automation && ./scripts/create-custom-domain-configs.sh test.example.com
```

This will create new files with your custom domain:
- `test.example.com-nonprod-namespaceconfig-rbac.yaml`
- `test.example.com-prod-namespaceconfig-rbac.yaml`

**Note:** Make sure to label your namespaces with the new domain:
```bash
oc label namespace <namespace-name> \
  test.example.com/mnemonic=<mnemonic> \
  test.example.com/app-environment=<environment>
```

## 📚 Documentation

- **[Deployment Guide](docs/redhat-cop-rbac-deployment-guide.md)** - Complete installation and testing instructions
- **[Verification Guide](docs/rbac-verification-guide.md)** - Comprehensive verification commands and expected outputs
- **[Scaling Guide](docs/scaling-system-namespace-access.md)** - How to add new system namespace access patterns
- **[Groups and Bindings Examples](docs/groups-and-bindings-examples.md)** - Examples of groups, RoleBindings, and ClusterRoleBindings with commands
- **[Final Architecture](FINAL_ARCHITECTURE.md)** - Complete architecture overview

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

**Expected behavior**: Template errors for namespace groups are normal - they indicate filtering is working.

## 🎯 Advanced: Modular GroupConfig Pattern

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