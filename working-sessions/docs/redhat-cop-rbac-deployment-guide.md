# OpenShift RBAC Automation - Deployment Guide

Complete deployment guide for enterprise-grade RBAC automation using Red Hat CoP Namespace Configuration Operator.

## 📋 Architecture Overview

**Core Components:**
- **Namespace RBAC**: Environment-aware namespace access control
- **Cluster RBAC**: Standard cluster-wide access patterns
- **System Access**: Automatic monitoring and system namespace access
- **Infrastructure Teams**: Dedicated platform team access
- **Standards Validation**: Optional Kyverno policy validation

## 🚀 Deployment Steps

### 1. Prerequisites

```bash
# Install Red Hat CoP Namespace Configuration Operator
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

# Wait for operator to be ready
oc wait --for=condition=Available --timeout=300s deployment/namespace-configuration-operator -n namespace-configuration-operator
```

### 2. Deploy RBAC Configurations

```bash
# Deploy namespace-level RBAC (environment-aware split configs)
oc apply -f policies/nonprod-namespaceconfig-rbac.yaml
oc apply -f policies/prod-namespaceconfig-rbac.yaml

# Deploy cluster-level RBAC (focused groupconfigs)
oc apply -f policies/cluster-admin-groupconfig-rbac.yaml
oc apply -f policies/cluster-developer-groupconfig-rbac.yaml
oc apply -f policies/cluster-audit-groupconfig-rbac.yaml

# Deploy system access and infrastructure groups
oc apply -f policies/database-admin-groupconfig-rbac.yaml
oc apply -f policies/user-workload-monitoring-admin-groupconfig-rbac.yaml

# Verify configurations are created
oc get namespaceconfig
oc get groupconfig
```

## 🧪 Testing Scenarios

### Scenario 1: Development Environment

```bash
# Create development namespace
oc new-project payment-dev
oc label namespace payment-dev \
  company.net/mnemonic=paym \
  company.net/app-environment=rnd

# Expected RoleBindings created:
# ✅ paym-admin-rb     (admin access)
# ✅ paym-developer-rb (edit access)  
# ✅ paym-audit-rb     (view access)

# Verify
oc get rolebindings -n payment-dev
```

### Scenario 2: Production Environment (Restricted)

```bash
# Create production namespace
oc new-project payment-prod
oc label namespace payment-prod \
  company.net/mnemonic=paym \
  company.net/app-environment=prod

# Expected RoleBindings created:
# ❌ paym-admin-rb     (NO admin access in prod!)
# ❌ paym-developer-rb (NO edit access in prod!)
# ✅ paym-audit-rb     (view access only)

# Verify production restrictions
oc get rolebindings -n payment-prod
oc get rolebindings -n payment-prod -l rbac.ocp.io/role-type=ns-admin
# Expected: No resources found

oc get rolebindings -n payment-prod -l rbac.ocp.io/role-type=ns-developer
# Expected: No resources found

oc get rolebindings -n payment-prod -l rbac.ocp.io/role-type=ns-audit
# Expected: paym-audit-rb found
```

### Scenario 3: Cluster-Level RBAC

```bash
# Group Sync Operator creates these groups (automatic):
# app-ocp-rbac-frontend-cluster-admin
# app-ocp-rbac-backend-cluster-developer
# app-ocp-rbac-security-cluster-audit

# Expected ClusterRoleBindings created automatically:
# ✅ app-ocp-rbac-frontend-cluster-admin-crb  → admin
# ✅ app-ocp-rbac-backend-cluster-developer-crb → edit
# ✅ app-ocp-rbac-security-cluster-audit-crb → view

# Verify cluster RBAC
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

### Scenario 4: System Monitoring Access

```bash
# All ns-admin and ns-developer groups automatically get monitoring access
# No additional configuration required

# Verify monitoring access for a team
oc get rolebindings -n openshift-user-workload-monitoring | grep paym

# Expected RoleBindings created automatically:
# ✅ app-ocp-rbac-paym-ns-admin-monitoring-config-edit       (monitoring config)
# ✅ app-ocp-rbac-paym-ns-developer-monitoring-config-edit   (monitoring config)
# ✅ app-ocp-rbac-paym-ns-admin-prometheus-rules-edit        (prometheus rules - admin only)
# ✅ app-ocp-rbac-paym-ns-admin-alert-routing-edit           (alertmanager - admin only)

# Verify system access
oc get rolebindings -n openshift-user-workload-monitoring -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

### Scenario 5: Infrastructure Teams

```bash
# Infrastructure teams get automatic cluster-wide access
# Group Sync Operator creates these groups:
# - platform-database-admins
# - security-compliance-team
# - network-operations-team
# - backup-recovery-team
# - monitoring-team

# Expected ClusterRoleBindings created automatically:
# ✅ platform-database-admins-crb     → database-cluster-admin
# ✅ security-compliance-crb          → security-policy-manager
# ✅ network-operations-crb           → network-infrastructure-admin
# ✅ backup-recovery-crb              → backup-operator-admin
# ✅ monitoring-team-crb              → monitoring-infrastructure-admin

# Verify infrastructure team access
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator | grep dedicated
```

## ✅ Verification Commands

### Namespace-Level Verification

```bash
# List all managed RoleBindings
oc get rolebindings -A -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check environment-specific access levels
oc get rolebindings -A -l rbac.ocp.io/access-level=admin-non-prod-only
oc get rolebindings -A -l rbac.ocp.io/access-level=developer-non-prod-only
oc get rolebindings -A -l rbac.ocp.io/access-level=audit-all-environments

# Verify no admin/edit in production
oc get rolebindings -A -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-admin
oc get rolebindings -A -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-developer
# Both should return: No resources found

# Verify audit access exists in production
oc get rolebindings -A -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-audit
# Should show audit RoleBindings
```

### Cluster-Level Verification

```bash
# List all managed ClusterRoleBindings
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check team-based groupings
oc get clusterrolebindings -l rbac.ocp.io/team=frontend
oc get clusterrolebindings -l rbac.ocp.io/team=backend

# Verify role mappings
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-admin --show-labels
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-developer --show-labels
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-audit --show-labels
```

> **📚 For detailed examples and commands**: See [Groups and Bindings Examples](./groups-and-bindings-examples.md) for comprehensive examples of viewing groups, ClusterRoleBindings, and RoleBindings with practical commands.

### System Access Verification

```bash
# Verify monitoring access bindings
oc get rolebindings -n openshift-user-workload-monitoring -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check specific monitoring role assignments
oc get rolebindings -A -l rbac.ocp.io/specific-role=user-workload-monitoring-config-edit
oc get rolebindings -A -l rbac.ocp.io/specific-role=monitoring-rules-edit
oc get rolebindings -A -l rbac.ocp.io/specific-role=alert-routing-edit

# Verify infrastructure team ClusterRoleBindings
oc get clusterrolebindings -l rbac.ocp.io/role-type=dedicated-database-platform
oc get clusterrolebindings -l rbac.ocp.io/role-type=dedicated-security-compliance
oc get clusterrolebindings -l rbac.ocp.io/role-type=dedicated-network-operations

# Check system access configurations status
oc get groupconfig dedicated-custom-groups -o yaml
oc get groupconfig user-workload-monitoring-access -o yaml
```

### Configuration Status Check

```bash
# Check NamespaceConfig status
oc get namespaceconfig mnemonic-environment-rbac -o yaml

# Check GroupConfig status
oc get groupconfig universal-cluster-rbac -o yaml

# Monitor operator logs
oc logs -n namespace-configuration-operator deployment/namespace-configuration-operator --tail=20
```

## 🔧 Troubleshooting

### RoleBindings Not Created

```bash
# Check namespace has required labels
oc get namespace <namespace-name> --show-labels
# Should have both: company.net/mnemonic and company.net/app-environment

# Check NamespaceConfig selector matches
oc get namespaceconfig mnemonic-environment-rbac -o jsonpath='{.spec.selector}'

# Check operator logs for errors
oc logs -n namespace-configuration-operator deployment/namespace-configuration-operator | grep ERROR
```

### ClusterRoleBindings Not Created

```bash
# List all groups to verify naming pattern
oc get groups | grep app-ocp-rbac | grep cluster

# Check GroupConfig is processing groups
oc describe groupconfig universal-cluster-rbac

# Verify groups match the pattern
oc get groups | grep "app-ocp-rbac.*cluster.*"
```

> **📚 For more troubleshooting commands**: See [Groups and Bindings Examples](./groups-and-bindings-examples.md) for additional verification and troubleshooting commands.

## 📊 Complete Access Matrix

| Environment | Admin Access | Developer Access | Audit Access |
|-------------|--------------|------------------|--------------|
| **rnd**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **eng**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **qa**      | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **uat**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **prod**    | ❌ **No**    | ❌ **No**        | ✅ Yes       |

## 🎯 Benefits of This Solution

1. **✅ Environment Security**: Automatic production restrictions
2. **✅ Mnemonic-Driven**: Uses existing company.net/mnemonic labels
3. **✅ Pattern-Based**: Leverages group naming conventions
4. **✅ Team-Friendly**: No complex policy management needed
5. **✅ Automatic**: Works with Group Sync Operator out of the box
6. **✅ Scalable**: Handles unlimited teams and environments
7. **✅ Auditable**: Rich labeling and annotations for compliance

## 🎛️ Optional: Standards Enforcement with Kyverno

For additional governance, deploy Kyverno validation policies:

```bash
# Install Kyverno (if not already installed)
oc apply -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml

# Deploy RBAC standards validation
oc apply -f policies/kyverno-validation-only.yaml

# Verify policy is active
oc get clusterpolicy rbac-standards-enforcement
```

### What Kyverno Validates:
- **Mnemonic format**: Must be 4 lowercase letters (`^[a-z]{4}$`)
- **Environment values**: Must be `rnd`, `eng`, `qa`, `uat`, or `prod`
- **Group naming**: Must follow `app-ocp-rbac-{mnemonic}-(ns|cluster)-(admin|developer|audit)` pattern
- **Required labels**: Namespaces should have both mnemonic and environment labels

### Validation Mode:
- **Default**: `Audit` mode (logs violations, allows creation)
- **Enforcement**: Change to `Enforce` for blocking invalid resources

```bash
# Switch to enforcement mode
oc patch clusterpolicy rbac-standards-enforcement --type='merge' -p='{"spec":{"validationFailureAction":"Enforce"}}'

# Check violations (Audit mode)
oc get events --field-selector reason=PolicyViolation
```

## 🚀 Next Steps

1. **Deploy to non-production cluster first**
2. **Test with sample namespaces and groups**
3. **Verify environment restrictions work correctly**
4. **Optional: Deploy Kyverno validation for governance**
5. **Monitor for 2-3 weeks before production deployment**
6. **Train operations team on verification commands**

## 📚 Additional Resources

- **[Groups and Bindings Examples](./groups-and-bindings-examples.md)** - Comprehensive examples of groups, RoleBindings, and ClusterRoleBindings with practical commands for inspection and troubleshooting
- **[Scaling Guide](./scaling-system-namespace-access.md)** - How to add new system namespace access patterns
- **[Main README](../README.md)** - Overview and architecture documentation

Your RBAC automation workflow is now complete and production-ready! 🎉
