# RBAC Automation Verification Guide

Complete verification guide for validating your OpenShift RBAC automation deployment.

## 🎯 Overview

This guide provides comprehensive verification commands to ensure your RBAC automation is correctly configured and operating as designed.

---

## 📋 **1. Verify All Deployed Configurations**

### List All Configs

```bash
# List all NamespaceConfigs, GroupConfigs, and UserConfigs
oc get namespaceconfig,groupconfig,userconfig
```

**Expected Output:**
```
NAME                                                               AGE
namespaceconfig.redhatcop.redhat.io/multitenant                    96d
namespaceconfig.redhatcop.redhat.io/nonprod-namespaceconfig-rbac   30m
namespaceconfig.redhatcop.redhat.io/prod-namespaceconfig-rbac      98d

NAME                                                                                  AGE
groupconfig.redhatcop.redhat.io/cluster-admin-groupconfig-rbac                        96d
groupconfig.redhatcop.redhat.io/cluster-audit-groupconfig-rbac                        50s
groupconfig.redhatcop.redhat.io/cluster-developer-groupconfig-rbac                    98d
groupconfig.redhatcop.redhat.io/database-admin-groupconfig-rbac                       47s
groupconfig.redhatcop.redhat.io/user-workload-monitoring-admin-groupconfig-rbac       96d
groupconfig.redhatcop.redhat.io/user-workload-monitoring-developer-groupconfig-rbac   96d

NAME                                                               AGE
userconfig.redhatcop.redhat.io/test-deletion-tracking-userconfig   96d
```

---

## 🔒 **2. Verify Non-Production Namespace RBAC**

### Check RoleBindings in Non-Prod Namespace

```bash
# Check RoleBindings in a non-prod namespace (should have 3: admin, developer, audit)
oc get rolebindings -n beta-rnd -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

**Expected Output:**
```
NAME                ROLE                AGE
beta-admin-rb       ClusterRole/admin   30m
beta-audit-rb       ClusterRole/view    30m
beta-developer-rb   ClusterRole/edit    30m
```

### Verify Group-to-Role Mapping (Non-Prod)

```bash
# Verify exact group names and role assignments
oc get rolebindings -n beta-rnd beta-admin-rb beta-developer-rb beta-audit-rb -o json | \
  jq -r '.items[] | "\(.metadata.name) | Group: \(.subjects[0].name) | Role: \(.roleRef.name)"'
```

**Expected Output:**
```
beta-admin-rb | Group: app-ocp-rbac-beta-ns-admin | Role: admin
beta-developer-rb | Group: app-ocp-rbac-beta-ns-developer | Role: edit
beta-audit-rb | Group: app-ocp-rbac-beta-ns-audit | Role: view
```

**✅ Verification:**
- ✅ **3 RoleBindings** created (admin, developer, audit)
- ✅ Groups follow pattern: `app-ocp-rbac-{mnemonic}-ns-{role}`
- ✅ Roles correctly mapped: admin → admin, developer → edit, audit → view

---

## 🔒 **3. Verify Production Namespace RBAC**

### Check RoleBindings in Prod Namespace

```bash
# Check RoleBindings in a prod namespace (should have 2: developer, audit - NO ADMIN)
oc get rolebindings -n beta-prod -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

**Expected Output:**
```
NAME                ROLE               AGE
beta-audit-rb       ClusterRole/view   96d
beta-developer-rb   ClusterRole/edit   96d
```

**⚠️ CRITICAL:** Notice there is **NO beta-admin-rb** - this is correct for production!

### Verify Group-to-Role Mapping (Prod)

```bash
# Verify exact group names and role assignments
oc get rolebindings -n beta-prod beta-developer-rb beta-audit-rb -o json | \
  jq -r '.items[] | "\(.metadata.name) | Group: \(.subjects[0].name) | Role: \(.roleRef.name)"'
```

**Expected Output:**
```
beta-developer-rb | Group: app-ocp-rbac-beta-ns-developer | Role: edit
beta-audit-rb | Group: app-ocp-rbac-beta-ns-audit | Role: view
```

**✅ Verification:**
- ✅ **2 RoleBindings** created (developer, audit)
- ❌ **NO admin RoleBinding** (correct for production security)
- ✅ Same groups as non-prod, but restricted permissions

---

## 🌐 **4. Verify Cluster-Level RBAC**

### List All Managed ClusterRoleBindings

```bash
# List all ClusterRoleBindings managed by namespace-configuration-operator
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

**Expected Output:**
```
NAME                                          ROLE                AGE
app-ocp-rbac-alpha-cluster-admin-crb          ClusterRole/admin   96d
app-ocp-rbac-alpha-cluster-audit-crb          ClusterRole/view    21s
app-ocp-rbac-alpha-cluster-developer-crb      ClusterRole/view    98d
app-ocp-rbac-demo-cluster-admin-crb           ClusterRole/admin   96d
app-ocp-rbac-demo-cluster-audit-crb           ClusterRole/view    21s
app-ocp-rbac-demo-cluster-developer-crb       ClusterRole/view    98d
...
```

### Verify Cluster Group-to-Role Mapping

```bash
# Verify cluster-level group and role assignments for alpha team
oc get clusterrolebindings app-ocp-rbac-alpha-cluster-admin-crb \
  app-ocp-rbac-alpha-cluster-developer-crb \
  app-ocp-rbac-alpha-cluster-audit-crb -o json | \
  jq -r '.items[] | "\(.metadata.name) | Group: \(.subjects[0].name) | ClusterRole: \(.roleRef.name)"'
```

**Expected Output:**
```
app-ocp-rbac-alpha-cluster-admin-crb | Group: app-ocp-rbac-alpha-cluster-admin | ClusterRole: admin
app-ocp-rbac-alpha-cluster-developer-crb | Group: app-ocp-rbac-alpha-cluster-developer | ClusterRole: view
app-ocp-rbac-alpha-cluster-audit-crb | Group: app-ocp-rbac-alpha-cluster-audit | ClusterRole: view
```

### Check Specific Cluster Group Types

```bash
# Check cluster-admin ClusterRoleBindings
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-admin

# Check cluster-developer ClusterRoleBindings
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-developer

# Check cluster-audit ClusterRoleBindings
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-audit
```

**✅ Verification:**
- ✅ Groups follow pattern: `app-ocp-rbac-{mnemonic}-cluster-{role}`
- ✅ cluster-admin groups → admin ClusterRole
- ✅ cluster-developer groups → view ClusterRole
- ✅ cluster-audit groups → view ClusterRole

---

## 👥 **5. Verify Groups**

### List All Namespace-Level Groups

```bash
# List all namespace-level groups
oc get groups | grep "ns-admin\|ns-developer\|ns-audit"
```

**Expected Output:**
```
app-ocp-rbac-alpha-ns-admin               jane.smith
app-ocp-rbac-alpha-ns-audit               bob.wilson
app-ocp-rbac-alpha-ns-developer           jane.smith, bob.wilson
app-ocp-rbac-beta-ns-admin                jane.smith, alice.cooper
app-ocp-rbac-beta-ns-audit                bob.wilson
app-ocp-rbac-beta-ns-developer            bob.wilson
app-ocp-rbac-demo-ns-admin                john.doe, jane.smith
app-ocp-rbac-demo-ns-audit                bob.wilson
app-ocp-rbac-demo-ns-developer            jane.smith, bob.wilson, sarah.jones
...
```

### List All Cluster-Level Groups

```bash
# List all cluster-level groups
oc get groups | grep "cluster-admin\|cluster-developer\|cluster-audit"
```

**Expected Output:**
```
app-ocp-rbac-alpha-cluster-admin          jane.smith
app-ocp-rbac-alpha-cluster-audit          bob.wilson
app-ocp-rbac-alpha-cluster-developer      jane.smith, bob.wilson
app-ocp-rbac-demo-cluster-admin           john.doe
app-ocp-rbac-demo-cluster-audit           bob.wilson
app-ocp-rbac-demo-cluster-developer       jane.smith
...
```

**✅ Verification:**
- ✅ Groups synced from LDAP via Group Sync Operator
- ✅ Naming pattern followed: `app-ocp-rbac-{mnemonic}-(ns|cluster)-{role}`
- ✅ Members populated from LDAP

---

## 📊 **6. Verify Monitoring Access**

### Check Monitoring RoleBindings

```bash
# Check monitoring RoleBindings created for ns-admin groups
oc get rolebindings -n openshift-user-workload-monitoring \
  -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

**Expected Output:**
```
NAME                                                   ROLE                                     AGE
app-ocp-rbac-alpha-ns-admin-alert-routing-edit         Role/alert-routing-edit                  96d
app-ocp-rbac-alpha-ns-admin-monitoring-config-edit     Role/user-workload-monitoring-config-edit 96d
app-ocp-rbac-alpha-ns-admin-prometheus-rules-edit      ClusterRole/monitoring-rules-edit        96d
app-ocp-rbac-beta-ns-admin-alert-routing-edit          Role/alert-routing-edit                  96d
app-ocp-rbac-beta-ns-admin-monitoring-config-edit      Role/user-workload-monitoring-config-edit 96d
app-ocp-rbac-beta-ns-admin-prometheus-rules-edit       ClusterRole/monitoring-rules-edit        96d
app-ocp-rbac-demo-ns-developer-monitoring-config-edit  Role/user-workload-monitoring-config-edit 96d
...
```

**✅ Verification:**
- ✅ **ns-admin groups** get 3 RoleBindings:
  - monitoring-config-edit (Role)
  - prometheus-rules-edit (ClusterRole)
  - alert-routing-edit (Role)
- ✅ **ns-developer groups** get 1 RoleBinding:
  - monitoring-config-edit (Role)

---

## 🔍 **7. Verify NamespaceConfig Selectors**

### Check Nonprod Selector

```bash
# Verify nonprod NamespaceConfig selector
oc get namespaceconfig nonprod-namespaceconfig-rbac -o json | \
  jq '.spec.labelSelector'
```

**Expected Output:**
```json
{
  "matchExpressions": [
    {
      "key": "company.net/mnemonic",
      "operator": "Exists"
    },
    {
      "key": "company.net/app-environment",
      "operator": "In",
      "values": [
        "rnd",
        "eng",
        "qa",
        "uat"
      ]
    },
    {
      "key": "company.net/app-environment",
      "operator": "NotIn",
      "values": [
        "prod"
      ]
    }
  ]
}
```

### Check Prod Selector

```bash
# Verify prod NamespaceConfig selector
oc get namespaceconfig prod-namespaceconfig-rbac -o json | \
  jq '.spec.labelSelector'
```

**Expected Output:**
```json
{
  "matchExpressions": [
    {
      "key": "company.net/mnemonic",
      "operator": "Exists"
    },
    {
      "key": "company.net/app-environment",
      "operator": "In",
      "values": [
        "prod"
      ]
    }
  ]
}
```

**✅ Verification:**
- ✅ Nonprod selector targets: rnd, eng, qa, uat
- ✅ Nonprod selector explicitly excludes: prod
- ✅ Prod selector targets: prod only
- ✅ No overlap between selectors

---

## 🔍 **8. Verify GroupConfig Selectors**

### Check All GroupConfig Selectors

```bash
# Verify all GroupConfigs use LDAP sync provider selector
oc get groupconfig -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.spec.labelSelector.matchExpressions[0].key) \(.spec.labelSelector.matchExpressions[0].operator)"'
```

**Expected Output:**
```
cluster-admin-groupconfig-rbac: group-sync-operator.redhat-cop.io/sync-provider Exists
cluster-audit-groupconfig-rbac: group-sync-operator.redhat-cop.io/sync-provider Exists
cluster-developer-groupconfig-rbac: group-sync-operator.redhat-cop.io/sync-provider Exists
database-admin-groupconfig-rbac: group-sync-operator.redhat-cop.io/sync-provider Exists
user-workload-monitoring-admin-groupconfig-rbac: group-sync-operator.redhat-cop.io/sync-provider Exists
user-workload-monitoring-developer-groupconfig-rbac: group-sync-operator.redhat-cop.io/sync-provider Exists
```

**✅ Verification:**
- ✅ All GroupConfigs use consistent selector
- ✅ Only LDAP-synced groups are processed
- ✅ Template filtering handles group name patterns

---

## 🧪 **9. Test Namespace Labeling**

### Test Non-Prod Namespace

```bash
# Create test non-prod namespace
oc new-project test-payment-dev
oc label namespace test-payment-dev \
  company.net/mnemonic=paym \
  company.net/app-environment=rnd

# Wait a few seconds for reconciliation
sleep 5

# Verify RoleBindings created
oc get rolebindings -n test-payment-dev -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected: 3 RoleBindings (admin, developer, audit)
```

### Test Prod Namespace

```bash
# Create test prod namespace
oc new-project test-payment-prod
oc label namespace test-payment-prod \
  company.net/mnemonic=paym \
  company.net/app-environment=prod

# Wait a few seconds for reconciliation
sleep 5

# Verify RoleBindings created
oc get rolebindings -n test-payment-prod -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected: 2 RoleBindings (developer, audit - NO ADMIN)
```

### Cleanup Test Namespaces

```bash
# Delete test namespaces
oc delete project test-payment-dev test-payment-prod
```

---

## 📊 **10. Security Verification Matrix**

### Verify Production Security

```bash
# Verify NO admin RoleBindings exist in prod namespaces
oc get rolebindings -A \
  -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-admin

# Expected: No resources found (this is correct!)
```

### Verify Non-Prod Access

```bash
# Verify admin RoleBindings exist in non-prod namespaces
oc get rolebindings -A \
  -l rbac.ocp.io/environment=rnd,rbac.ocp.io/role-type=ns-admin

# Expected: List of admin RoleBindings in rnd environments
```

---

## 🔧 **11. Verify LDAP Group Sync**

### Check GroupSync Status

```bash
# View GroupSync configuration and status
oc get groupsync -n group-sync-operator ldap-groupsync -o yaml
```

**Key Fields to Check:**
- `spec.schedule`: Sync frequency (e.g., `*/2 * * * *` = every 2 minutes)
- `status.lastSyncSuccessTime`: When last sync succeeded
- `status.conditions`: Check for ReconcileSuccess

### Force Group Sync

```bash
# Trigger manual group sync (if needed)
oc annotate groupsync ldap-groupsync -n group-sync-operator \
  test-trigger=$(date +%s) --overwrite
```

---

## ✅ **Complete Verification Checklist**

Use this checklist to confirm your deployment:

- [ ] All NamespaceConfigs deployed and reconciling successfully
- [ ] All GroupConfigs deployed and reconciling successfully
- [ ] Non-prod namespaces have 3 RoleBindings (admin, developer, audit)
- [ ] Prod namespaces have 2 RoleBindings (developer, audit - NO admin)
- [ ] Cluster-admin groups have admin ClusterRole
- [ ] Cluster-developer groups have view ClusterRole
- [ ] Cluster-audit groups have view ClusterRole
- [ ] ns-admin groups have monitoring access (3 RoleBindings)
- [ ] ns-developer groups have monitoring config access (1 RoleBinding)
- [ ] All groups follow naming pattern: `app-ocp-rbac-{mnemonic}-(ns|cluster)-{role}`
- [ ] LDAP GroupSync is running and syncing successfully
- [ ] No admin access in production namespaces
- [ ] Selectors correctly target intended environments

---

## 🎯 **Expected Behavior Summary**

### Non-Production Environments (rnd, eng, qa, uat)
- ✅ **Admin access** (admin ClusterRole)
- ✅ **Developer access** (edit ClusterRole)
- ✅ **Audit access** (view ClusterRole)
- ✅ **Monitoring access** (full for admin, config-only for developer)

### Production Environment (prod)
- ❌ **NO Admin access**
- ✅ **Developer access** (edit ClusterRole)
- ✅ **Audit access** (view ClusterRole)
- ✅ **Monitoring access** (full for admin, config-only for developer)

### Cluster-Level Access
- ✅ **cluster-admin groups** → admin ClusterRole
- ✅ **cluster-developer groups** → view ClusterRole
- ✅ **cluster-audit groups** → view ClusterRole

---

## 🚨 **Troubleshooting**

### RoleBindings Not Created

```bash
# Check namespace has required labels
oc get namespace <namespace-name> --show-labels

# Verify NamespaceConfig is reconciling
oc get namespaceconfig nonprod-namespaceconfig-rbac -o yaml | grep -A 5 status

# Check operator logs
oc logs -n namespace-configuration-operator \
  deployment/namespace-configuration-operator --tail=50
```

### Wrong Permissions in Production

```bash
# Verify environment label is exactly "prod"
oc get namespace <namespace-name> -o yaml | grep app-environment

# Check which NamespaceConfig matched
oc get rolebindings -n <namespace-name> -o yaml | grep source-namespaceconfig
```

### Groups Not Syncing

```bash
# Check GroupSync status
oc get groupsync -n group-sync-operator ldap-groupsync

# View sync errors
oc get groupsync -n group-sync-operator ldap-groupsync -o yaml | grep -A 10 conditions
```

---

**🎉 Your RBAC automation verification is complete!**
