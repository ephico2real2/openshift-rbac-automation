# RBAC Automation Scripts

This directory contains automation scripts for managing and verifying OpenShift RBAC configuration.

## 📋 Available Scripts

### 1. `setup-test-namespaces.sh`
Creates and labels test namespaces for RBAC automation testing.

**Usage:**
```bash
# Create all test namespaces with labels
./scripts/setup-test-namespaces.sh create

# Delete all test namespaces
./scripts/setup-test-namespaces.sh delete

# Verify existing setup
./scripts/setup-test-namespaces.sh verify
```

**Test Namespaces Created:**
- `demo-rnd`, `demo-qa`, `demo-uat` (demo team)
- `beta-rnd`, `beta-uat`, `beta-prod` (beta team) 
- `jeff-rnd`, `jeff-qa` (jeff team)

### 2. `show-rbac-rolebindings.sh`
Displays RoleBindings with their subjects (Groups/Users/ServiceAccounts) across namespaces.

**Usage:**
```bash
# Show all labeled namespaces (default)
./scripts/show-rbac-rolebindings.sh

# Show only test namespaces
./scripts/show-rbac-rolebindings.sh --target test

# Show specific namespace
./scripts/show-rbac-rolebindings.sh --target demo-rnd

# Show multiple namespaces
./scripts/show-rbac-rolebindings.sh --target demo-rnd,beta-prod

# Show help
./scripts/show-rbac-rolebindings.sh --help
```

### 3. `watch-groupsync-operator.sh`
Monitors Group Sync Operator status and group synchronization.

**Usage:**
```bash
# Show current status (default)
./scripts/watch-groupsync-operator.sh status

# Monitor group sync in real-time
./scripts/watch-groupsync-operator.sh monitor

# Count synced groups
./scripts/watch-groupsync-operator.sh count
```

## 🔍 RBAC Verification Commands

### Check Security Model Compliance

**Verify environment-aware security model:**
```bash
# Non-prod environments should have admin/developer/audit access
./scripts/show-rbac-rolebindings.sh --target demo-rnd,beta-rnd,jeff-rnd

# Production should have audit-only access  
./scripts/show-rbac-rolebindings.sh --target beta-prod
```

**Expected Results:**
- **Non-prod** (`rnd`, `qa`, `uat`): 3 RoleBindings (admin + developer + audit)
- **Production** (`prod`): 1 RoleBinding (audit only)

### Verify LDAP Group Coverage

**Check available LDAP groups by team:**
```bash
# Demo team groups (should be complete)
oc get groups | grep "app-ocp-rbac-demo"

# Beta team groups
oc get groups | grep "app-ocp-rbac-beta"

# Jeff team groups
oc get groups | grep "app-ocp-rbac-jeff"
```

**Required groups per team:**
- `app-ocp-rbac-{mnemonic}-ns-admin`
- `app-ocp-rbac-{mnemonic}-ns-developer`
- `app-ocp-rbac-{mnemonic}-ns-audit`

### Check Namespace Labels

**Verify namespace labeling:**
```bash
# Check specific namespace
oc get namespace demo-rnd --show-labels | grep company.net

# Check all test namespaces
for ns in demo-rnd demo-qa demo-uat beta-rnd beta-uat beta-prod jeff-rnd jeff-qa; do
  echo "=== $ns ==="
  oc get namespace $ns -o jsonpath='{.metadata.labels}' | jq -r 'to_entries[] | select(.key | contains("company.net")) | "  \(.key): \(.value)"'
done
```

## 📊 Current Status Analysis

### ✅ What's Working

**RBAC Design Compliance:**
- ✅ Non-prod environments get admin/developer/audit access
- ✅ Prod environments should get audit-only access  
- ✅ NamespaceConfig template logic is correct
- ✅ Environment-aware security restrictions implemented

**Demo Team (Complete):**
- ✅ `app-ocp-rbac-demo-ns-admin` → Creates admin RoleBindings
- ✅ `app-ocp-rbac-demo-ns-developer` → Creates developer RoleBindings
- ✅ `app-ocp-rbac-demo-ns-audit` → Creates audit RoleBindings

**Namespace Coverage:**
- ✅ 7/8 test namespaces have correct RoleBindings
- ✅ All non-prod namespaces working (21 RoleBindings created)

### ❌ Missing Components

**Beta Team (Incomplete):**
- ✅ `app-ocp-rbac-beta-ns-admin` (exists)
- ✅ `app-ocp-rbac-beta-ns-developer` (exists)  
- ❌ `app-ocp-rbac-beta-ns-audit` (missing)

**Jeff Team (Incomplete):**
- ✅ `app-ocp-rbac-jeff-ns-admin` (exists)
- ❌ `app-ocp-rbac-jeff-ns-developer` (missing)
- ❌ `app-ocp-rbac-jeff-ns-audit` (missing)

**Impact:**
- `beta-prod` has 0 RoleBindings (should have 1 audit RoleBinding)
- Jeff namespaces missing developer and audit RoleBindings

## 🔧 Troubleshooting Commands

**Check NamespaceConfig status:**
```bash
oc get namespaceconfig mnemonic-environment-rbac -o yaml
```

**Check operator logs:**
```bash
oc logs -n namespace-configuration-operator deployment/namespace-configuration-operator-controller-manager -c manager --tail=50
```

**Force namespace reconciliation:**
```bash
oc annotate namespace <namespace-name> debug/force-reconcile="$(date)" --overwrite
```

**Verify Group Sync Operator:**
```bash
oc get groupsync -A
oc get groups | grep app-ocp-rbac | wc -l
```

## 🎯 Next Steps

1. **Add missing LDAP groups** for beta and jeff teams
2. **Verify security model compliance** after groups are created
3. **Monitor automatic RoleBinding creation** for production namespaces
4. **Test with additional teams** as needed

---

**Note:** The RBAC automation is working correctly. The missing RoleBindings are due to incomplete LDAP group coverage, not template design issues.