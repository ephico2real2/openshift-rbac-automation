# Scaling System Namespace Access

This guide shows how to easily add new system namespace access patterns following our established naming convention.

## 🎯 **Naming Pattern for Scalability**

| Purpose | File Name | Object Name | Component Label |
|---------|-----------|-------------|-----------------|
| **Monitoring** | `redhat-cop-user-workload-monitoring.yaml` | `user-workload-monitoring-access` | `user-workload-monitoring` |
| **Registry** | `redhat-cop-image-registry-access.yaml` | `image-registry-access` | `image-registry-access` |
| **Logging** | `redhat-cop-cluster-logging-access.yaml` | `cluster-logging-access` | `cluster-logging-access` |
| **Custom CRDs** | See `docs/examples/` for template | N/A | N/A |

## 📋 **Template for New System Access**

### **Step 1: Create New Policy File**

```bash
# Name pattern: redhat-cop-{system-name}-access.yaml
cp policies/redhat-cop-user-workload-monitoring.yaml policies/redhat-cop-{system-name}-access.yaml
```

### **Step 2: Update Metadata**

```yaml
apiVersion: redhatcop.redhat.io/v1alpha1
kind: GroupConfig
metadata:
  name: {system-name}-access                    # Match file purpose
  labels:
    app.kubernetes.io/name: namespace-configuration-operator
    app.kubernetes.io/component: {system-name}-access  # Match file purpose
  annotations:
    description: "Grant ns-admin and ns-developer groups access to {system description}"
```

### **Step 3: Add Role Templates**

```yaml
spec:
  selector:
    matchExpressions:
    # Standard selector - same for all system access policies
    - key: metadata.name
      operator: MatchesRegex
      values: 
      - "^app-ocp-rbac-[a-z]{4}-ns-(admin|developer)$"
  templates:
    # Template for each role needed
    - objectTemplate: |
        {{- if contains "-ns-admin" .Name }}  # Admin-only access
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          name: "{{ .Name }}-{role-name}"
          namespace: {target-namespace}
          labels:
            app.kubernetes.io/managed-by: namespace-configuration-operator
            rbac.ocp.io/role-type: {system-name}-access
            rbac.ocp.io/target-namespace: {target-namespace}
            rbac.ocp.io/source-group: "{{ .Name }}"
            rbac.ocp.io/specific-role: {role-name}
        subjects:
        - kind: Group
          name: "{{ .Name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          kind: ClusterRole  # or Role
          name: {clusterrole-name}
          apiGroup: rbac.authorization.k8s.io
        {{- end }}
```

## 🚀 **Real Examples**

### **Example 1: OpenShift Logging Access**

```bash
# File: policies/redhat-cop-cluster-logging-access.yaml
```

```yaml
apiVersion: redhatcop.redhat.io/v1alpha1
kind: GroupConfig
metadata:
  name: cluster-logging-access
  labels:
    app.kubernetes.io/name: namespace-configuration-operator
    app.kubernetes.io/component: cluster-logging-access
  annotations:
    description: "Grant ns-admin groups access to cluster logging configuration"
spec:
  selector:
    matchExpressions:
    - key: metadata.name
      operator: MatchesRegex
      values: 
      - "^app-ocp-rbac-[a-z]{4}-ns-admin$"  # Admin only
  templates:
    - objectTemplate: |
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          name: "{{ .Name }}-logging-admin"
          namespace: openshift-logging
          labels:
            app.kubernetes.io/managed-by: namespace-configuration-operator
            rbac.ocp.io/role-type: cluster-logging-access
            rbac.ocp.io/target-namespace: openshift-logging
            rbac.ocp.io/source-group: "{{ .Name }}"
            rbac.ocp.io/specific-role: cluster-logging-operator-admin
        subjects:
        - kind: Group
          name: "{{ .Name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          kind: ClusterRole
          name: cluster-logging-operator-admin
          apiGroup: rbac.authorization.k8s.io
```

### **Example 2: Image Registry Access**

```bash
# File: policies/redhat-cop-image-registry-access.yaml
```

```yaml
apiVersion: redhatcop.redhat.io/v1alpha1
kind: GroupConfig
metadata:
  name: image-registry-access
  labels:
    app.kubernetes.io/name: namespace-configuration-operator
    app.kubernetes.io/component: image-registry-access
  annotations:
    description: "Grant groups access to image registry configuration"
spec:
  selector:
    matchExpressions:
    - key: metadata.name
      operator: MatchesRegex
      values: 
      - "^app-ocp-rbac-[a-z]{4}-ns-(admin|developer)$"
  templates:
    - objectTemplate: |
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          name: "{{ .Name }}-registry-viewer"
          namespace: openshift-image-registry
          labels:
            app.kubernetes.io/managed-by: namespace-configuration-operator
            rbac.ocp.io/role-type: image-registry-access
            rbac.ocp.io/target-namespace: openshift-image-registry
            rbac.ocp.io/source-group: "{{ .Name }}"
            rbac.ocp.io/specific-role: registry-viewer
        subjects:
        - kind: Group
          name: "{{ .Name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          kind: ClusterRole
          name: registry-viewer
          apiGroup: rbac.authorization.k8s.io
```

## 🔧 **Deployment and Verification**

### **Deploy New System Access**
```bash
oc apply -f policies/redhat-cop-{system-name}-access.yaml

# Verify GroupConfig created
oc get groupconfig {system-name}-access -o yaml
```

### **Verify RoleBindings Created**
```bash
# Check for specific system access
oc get rolebindings -A -l rbac.ocp.io/role-type={system-name}-access

# Check specific role assignments  
oc get rolebindings -A -l rbac.ocp.io/specific-role={role-name}

# Check bindings in target namespace
oc get rolebindings -n {target-namespace} -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

## 📊 **Benefits of This Pattern**

1. **✅ Consistent Naming**: File name matches object name and component
2. **✅ Easy Discovery**: Clear what each policy does
3. **✅ Independent Scaling**: Add/remove system access without affecting others
4. **✅ Standard Structure**: Same template for all system access policies
5. **✅ Rich Metadata**: Labels enable precise filtering and monitoring

## 💡 **Best Practices**

- **One policy per system/namespace**: Keep concerns separated
- **Descriptive names**: Make purpose obvious from filename
- **Consistent labeling**: Use `rbac.ocp.io/*` labels for filtering
- **Document target namespace**: Clear which namespace gets the bindings
- **Test independently**: Each policy should work standalone

This pattern makes it trivial to add new system namespace access as your OpenShift cluster grows!