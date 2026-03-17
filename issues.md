# RBAC Automation Issues

## Issue #1: Red Hat CoP NamespaceConfig Multi-Template Processing Bug

**Date**: 2025-12-06  
**Status**: Resolved via workaround  
**Severity**: Medium  

### 🔍 Root Cause Analysis Summary

The exclusion principle testing revealed:

#### ✅ What Works
1. ✅ **Simple NamespaceConfig**: Works perfectly in prod environments  
2. ✅ **Exclusion logic**: `{{- if ne $env "prod" }}` correctly excludes prod
3. ✅ **Red Hat CoP operator**: Functions correctly with unconditional templates
4. ✅ **Group availability**: `app-ocp-rbac-beta-ns-audit` exists and is synced

#### ❌ The Problem
Our complex main NamespaceConfig with **multiple templates** is not creating the audit RoleBinding in prod, even though:
- The audit template has NO conditional logic
- Simple single-template configs work fine
- All prerequisites are met

### 🧪 Testing Evidence

**Test Case 1: Complex NamespaceConfig (3 templates)**
```yaml
# Attempted but failed: Combined conditional templates approach
templates:
  - admin (conditional: non-prod only)
  - developer (conditional: non-prod only) 
  - audit (unconditional: all environments)
```
**Result**: ❌ Audit RoleBinding NOT created in beta-prod

**Test Case 2: Simple NamespaceConfig (1 template)**
```yaml 
# Test: test-audit-only.yaml
templates:
  - audit (unconditional: all environments)
```
**Result**: ✅ Audit RoleBinding created successfully in beta-prod

### 🎯 Resolution Strategy

**Implemented Solution**: Split complex NamespaceConfig into environment-specific configs

1. **nonprod-namespaceconfig-rbac.yaml**
   - Scope: `rnd`, `eng`, `qa`, `uat` environments only
   - Templates: admin + developer + audit (no conditions needed)
   - Selector uses explicit environment allowlist

2. **prod-namespaceconfig-rbac.yaml**
   - Scope: `prod` environment only
   - Templates: audit only (unconditional)
   - Selector matches only production labeled namespaces

### 🔧 Technical Details

**Hypothesis**: Red Hat CoP Namespace Configuration Operator has issues processing multiple templates where:
- Some templates have complex Go template conditional logic (`{{- if ... }}`)
- Other templates are unconditional
- This appears to cause template parsing or application failures

**Workaround Benefits**:
- ✅ Eliminates conditional logic complexity
- ✅ Separates concerns (non-prod vs audit access)
- ✅ Easier to troubleshoot and maintain
- ✅ Clear separation of security scopes

### 📁 File Impact

**Working Solution Files** (currently in use):
- `policies/nonprod-namespaceconfig-rbac.yaml` - Non-production environments RBAC
- `policies/prod-namespaceconfig-rbac.yaml` - Production environment RBAC

**Failed Approach** (removed):
- `policies/redhat-cop-namespace-rbac-issues-not-working.yaml` - Combined conditional approach that didn't work

### 🎮 Verification Commands

```bash
# Apply working split configs
oc apply -f policies/nonprod-namespaceconfig-rbac.yaml
oc apply -f policies/prod-namespaceconfig-rbac.yaml

# Verify non-prod gets admin/developer/audit
oc get rolebindings -n beta-rnd -l app.kubernetes.io/managed-by=namespace-configuration-operator
oc get rolebindings -n demo-rnd -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Verify prod gets audit-only
oc get rolebindings -n beta-prod -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Expected results:
# Non-prod: 3 RoleBindings per namespace (admin + developer + audit)
# Prod: 1 RoleBinding per namespace (audit only)
```

### 📝 Lessons Learned

1. **Primary Root Cause**: Using `spec.selector` instead of `spec.labelSelector` (see Issue #2)
2. **Secondary Root Cause**: Conditional Go templates that evaluate to `false` produce empty/invalid output
   - When `{{- if ... }}` conditions are false, templates output empty strings
   - Red Hat CoP operator tries to parse empty output as Kubernetes resources
   - Results in `Object 'Kind' is missing in 'null'` errors
3. **Failed Workarounds**: Adding `{{- else }}` with comments doesn't work (comments aren't valid K8s resources)
4. **Solution**: Split into environment-specific NamespaceConfigs where all templates always produce valid resources
5. **Architecture Benefits**: Separation of concerns, cleaner debugging, better maintainability
6. **CRD Field Validation**: Always verify field names against actual CRD specifications
7. **Testing Strategy**: Test both positive and negative template conditions

---

## Issue #2: NamespaceConfig Selector Field Specification Error

**Date**: 2025-12-06  
**Status**: Resolved  
**Severity**: High  

### 🔍 Problem Description

The nonprod NamespaceConfig was creating admin RoleBindings in production namespaces despite having a selector that should only match non-production environments. Investigation revealed the root cause was using an incorrect field name in the CRD specification.

### 🧪 Symptoms Observed

**Unexpected Behavior**:
- `beta-admin-rb` RoleBinding appeared in `beta-prod` namespace
- RoleBinding had annotation: `rbac.ocp.io/source-namespaceconfig: nonprod-mnemonic-namespaceconfig-rbac`
- RoleBinding had label: `rbac.ocp.io/environment: prod` (should not match nonprod selector)

**Debugging Evidence**:
```bash
# Applied NamespaceConfig selector was null
oc get namespaceconfig nonprod-mnemonic-namespaceconfig-rbac -o json | jq '.spec.selector'
# Result: null
```

### 🔧 Root Cause Analysis

**Primary Issue**: Used incorrect CRD field name `selector` instead of `labelSelector`

**CRD Specification Analysis**:
```bash
oc get crd namespaceconfigs.redhatcop.redhat.io -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties}' | jq 'keys'
# Result: ["annotationSelector", "labelSelector", "templates"]
```

**Correct CRD Schema**:
- ✅ `spec.labelSelector` - For namespace label-based selection
- ✅ `spec.annotationSelector` - For namespace annotation-based selection  
- ✅ `spec.templates` - Resource templates to create
- ❌ `spec.selector` - **Does not exist in CRD**

### 📋 CRD Specification Details

#### labelSelector Structure
```yaml
spec:
  labelSelector:
    matchExpressions:  # Array of label selector requirements (ANDed)
      - key: string          # Required
        operator: string     # Required: In, NotIn, Exists, DoesNotExist
        values: [string]     # Required for In/NotIn, empty for Exists/DoesNotExist
    matchLabels:       # Map of key-value pairs (optional alternative)
      key: value       # Equivalent to matchExpressions with operator: In
```

#### templates Structure
```yaml
spec:
  templates:           # Array of resource templates
    - objectTemplate: string    # Required: Go template resolving to YAML API resource
      excludedPaths: [string]   # Optional: JSON paths excluded from LockedResourceReconciler
```

**Field Descriptions**:
- `objectTemplate`: "Go template. When processed, it must resolve to a yaml representation of an API resource"
- `excludedPaths`: "Set of json paths that need not be considered by the LockedResourceReconciler"
- `labelSelector`: "Selects Namespaces by label"
- `annotationSelector`: "Selects Namespaces by annotation"
- **Selector Logic**: "Selectors are considered in AND, so if multiple are defined they must all be true for a Namespace to be selected"

### 🎯 Resolution

**Applied Fix**: Changed `spec.selector` to `spec.labelSelector` in both configurations

**Before (Incorrect)**:
```yaml
spec:
  selector:  # ❌ Field does not exist in CRD
    matchExpressions:
      - key: company.net/app-environment
        operator: In
        values: ["rnd", "eng", "qa", "uat"]
```

**After (Correct)**:
```yaml
spec:
  labelSelector:  # ✅ Correct CRD field
    matchExpressions:
      - key: company.net/mnemonic
        operator: Exists
      - key: company.net/app-environment
        operator: In
        values: ["rnd", "eng", "qa", "uat"]
      - key: company.net/app-environment
        operator: NotIn
        values: ["prod"]  # Explicit prod exclusion
```

### 🧪 Verification

**Test Commands**:
```bash
# Verify selector is correctly parsed
oc get namespaceconfig nonprod-mnemonic-namespaceconfig-rbac -o json | jq '.spec.labelSelector'
oc get namespaceconfig prod-mnemonic-namespaceconfig-rbac -o json | jq '.spec.labelSelector'

# Verify no admin RoleBindings in prod
oc get rolebindings -n beta-prod | grep beta
# Expected: Only developer-rb and audit-rb, NO admin-rb
```

**Success Criteria**:
- ✅ Nonprod config matches only `rnd`, `eng`, `qa`, `uat` environments
- ✅ Prod config matches only `prod` environments  
- ✅ No selector overlap between configurations
- ✅ Admin RoleBindings excluded from production namespaces

### 📁 File Impact

**Modified Files**:
- `policies/nonprod-namespaceconfig-rbac.yaml`
- `policies/prod-namespaceconfig-rbac.yaml`

### 📝 Lessons Learned

1. **CRD Field Validation**: Always verify field names against the actual CRD specification
2. **Null Selectors**: When selectors are null/invalid, NamespaceConfig may match all namespaces
3. **Explicit Exclusion**: Use `NotIn` operators for explicit environment exclusion
4. **Field Naming**: Red Hat CoP operator uses `labelSelector`, not generic `selector`
5. **Testing Strategy**: Verify applied configuration structure using `oc get ... -o json | jq`

---

## Issue #3: Combined NamespaceConfig Still Failed After labelSelector Fix

**Date**: 2025-12-06  
**Status**: Unresolved - Split approach required  
**Severity**: High

### Summary
Even after fixing the `spec.selector` → `spec.labelSelector` field name issue in the combined NamespaceConfig approach, the configuration **still failed** due to conditional Go template processing issues. We had to split into **two separate NamespaceConfigs** as the final solution.

### What We Tried

#### 1. Fixed labelSelector Field ✅
```yaml
- spec:
-   selector:           # Wrong field name
+ spec:
+   labelSelector:      # Correct field name
      matchExpressions:
        - key: company.net/mnemonic
          operator: Exists
        - key: company.net/app-environment
          operator: Exists
```

#### 2. Added else Clauses to Prevent Empty Output ❌
```yaml
{{- if or (eq $env "rnd") (eq $env "eng") (eq $env "qa") (eq $env "uat") }}
# Valid RoleBinding YAML...
{{- else }}
# No admin RoleBinding for {{ $env }} environment
{{- end }}
```
**Result**: Still failed - comments are not valid Kubernetes resources

### Persistent Error
```
ERROR lockedresource unable to process template for
"error": "Object 'Kind' is missing in 'null'"
```

### Root Cause: Conditional Template Processing
- When Go template conditionals evaluate to `false` (e.g., for prod environments), they produce empty strings
- Red Hat CoP operator tries to parse empty output as valid Kubernetes resources
- Even with `{{- else }}` comments, the output isn't a valid API resource
- The operator cannot handle templates that sometimes produce valid resources and sometimes don't

### Final Solution: Split Approach ✅
We had to abandon the combined approach and use **two separate NamespaceConfigs**:

1. **nonprod-namespaceconfig-rbac.yaml** - All templates always produce valid resources for nonprod
2. **prod-namespaceconfig-rbac.yaml** - All templates always produce valid resources for prod

### Verification
```bash
# Working split approach
oc apply -f policies/nonprod-namespaceconfig-rbac.yaml
oc apply -f policies/prod-namespaceconfig-rbac.yaml
# Success: All RoleBindings created correctly

# Verify nonprod environments
oc get rolebindings -A -l rbac.ocp.io/environment=rnd,app.kubernetes.io/managed-by=namespace-configuration-operator

# Verify prod environment (audit only)
oc get rolebindings -A -l rbac.ocp.io/environment=prod,app.kubernetes.io/managed-by=namespace-configuration-operator
```

### Conclusion
The **split approach is mandatory**, not just preferred. The Red Hat CoP Namespace Configuration Operator cannot reliably handle mixed conditional/unconditional templates in a single configuration.

---

## Issue Template

```markdown
## Issue #N: [Title]

**Date**: YYYY-MM-DD  
**Status**: [Open|In Progress|Resolved|Won't Fix]  
**Severity**: [Low|Medium|High|Critical]  

### Problem Description
[Description]

### Root Cause
[Analysis]

### Resolution
[Solution]

### Verification
[Test commands]
```