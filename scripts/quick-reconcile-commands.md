# Quick Commands to Force Reconcile Cluster-Logging-Operator
## For OpenShift Logging 6.2+ (uses LokiStack CRD)

## Method 1: Delete Operator Pod (Simplest)
This forces the operator to restart and reconcile all resources:

```bash
# Delete the operator pod
oc delete pod -n openshift-logging -l name=cluster-logging-operator

# Wait for it to come back up
oc wait --for=condition=Ready pod -n openshift-logging -l name=cluster-logging-operator --timeout=300s
```

## Method 2: Annotate LokiStack CR
This triggers a reconciliation without restarting the operator:

```bash
# Get the LokiStack CR name
LS_NAME=$(oc get lokistack -n openshift-logging -o jsonpath='{.items[0].metadata.name}')

# Add reconcile annotation with timestamp
oc annotate lokistack/${LS_NAME} -n openshift-logging \
    reconcile=$(date +%s) --overwrite
```

## Method 3: Delete Problematic Loki Ingestor Pod
If a specific Loki ingestor pod is stuck:

```bash
# Find the problematic pod
oc get pods -n openshift-logging | grep -i "loki.*ingestor"

# Delete it (it will be recreated)
oc delete pod <pod-name> -n openshift-logging
```

## Troubleshooting Commands

### Check operator status:
```bash
oc get deployment -n openshift-logging cluster-logging-operator
oc get pods -n openshift-logging -l name=cluster-logging-operator
```

### Check Loki ingestor pods:
```bash
oc get pods -n openshift-logging | grep -i ingestor
oc get pods -n openshift-logging -l component=ingestor
```

### Check pod events and logs:
```bash
# Describe the problematic pod
oc describe pod <pod-name> -n openshift-logging

# Check logs
oc logs <pod-name> -n openshift-logging --tail=100

# Check events in namespace
oc get events -n openshift-logging --sort-by='.lastTimestamp' | tail -20
```

### Check LokiStack CR status:
```bash
oc get lokistack -n openshift-logging -o yaml
oc describe lokistack -n openshift-logging
```

### Check for resource constraints:
```bash
# Check if there are resource quota issues
oc describe quota -n openshift-logging

# Check node resources
oc top nodes
```


