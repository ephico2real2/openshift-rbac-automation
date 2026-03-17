#!/bin/bash
# Script to force reconcile cluster-logging-operator and troubleshoot Loki ingestor pods
# For OpenShift Logging 6.2+ (uses LokiStack CRD)
# Usage: ./force-reconcile-cluster-logging.sh

set -e

NAMESPACE="openshift-logging"
OPERATOR_NAME="cluster-logging-operator"

echo "=== Checking cluster-logging-operator status ==="
oc get deployment -n ${NAMESPACE} ${OPERATOR_NAME} || echo "Operator not found in ${NAMESPACE}"

echo -e "\n=== Current operator pods ==="
oc get pods -n ${NAMESPACE} -l name=${OPERATOR_NAME}

echo -e "\n=== Loki ingestor pods status ==="
oc get pods -n ${NAMESPACE} | grep -E "loki.*ingestor|ingestor.*loki" || echo "No Loki ingestor pods found"

echo -e "\n=== Checking LokiStack CR ==="
oc get lokistack -n ${NAMESPACE} -o yaml || echo "No LokiStack CR found"

echo -e "\n=== Method 1: Force reconcile by deleting operator pod ==="
echo "This will cause the operator to restart and reconcile all resources..."
read -p "Delete the operator pod to force reconcile? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    oc delete pod -n ${NAMESPACE} -l name=${OPERATOR_NAME}
    echo "Waiting for pod to restart..."
    oc wait --for=condition=Ready pod -n ${NAMESPACE} -l name=${OPERATOR_NAME} --timeout=300s
    echo "Operator pod restarted successfully"
fi

echo -e "\n=== Method 2: Force reconcile by annotating LokiStack CR ==="
LOKISTACK_NAME=$(oc get lokistack -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$LOKISTACK_NAME" ]; then
    echo "Found LokiStack CR: ${LOKISTACK_NAME}"
    read -p "Add reconcile annotation to force reconciliation? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oc annotate lokistack/${LOKISTACK_NAME} -n ${NAMESPACE} \
            reconcile=$(date +%s) --overwrite
        echo "Reconcile annotation added. Operator should reconcile shortly..."
    fi
else
    echo "No LokiStack CR found to annotate"
fi

echo -e "\n=== Method 3: Check and describe problematic Loki ingestor pod ==="
INGESTOR_POD=$(oc get pods -n ${NAMESPACE} | grep -E "loki.*ingestor|ingestor.*loki" | grep -v Running | awk '{print $1}' | head -1)
if [ -n "$INGESTOR_POD" ]; then
    echo "Found problematic pod: ${INGESTOR_POD}"
    echo -e "\n=== Pod description ==="
    oc describe pod ${INGESTOR_POD} -n ${NAMESPACE}
    echo -e "\n=== Pod logs ==="
    oc logs ${INGESTOR_POD} -n ${NAMESPACE} --tail=50 || echo "Could not retrieve logs"
    
    read -p "Delete this pod to force recreation? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oc delete pod ${INGESTOR_POD} -n ${NAMESPACE}
        echo "Pod deleted. Waiting for recreation..."
        sleep 10
        oc get pods -n ${NAMESPACE} | grep -E "loki.*ingestor|ingestor.*loki"
    fi
else
    echo "No problematic Loki ingestor pods found"
fi

echo -e "\n=== Final status check ==="
echo "Operator pods:"
oc get pods -n ${NAMESPACE} -l name=${OPERATOR_NAME}
echo -e "\nLoki ingestor pods:"
oc get pods -n ${NAMESPACE} | grep -E "loki.*ingestor|ingestor.*loki"


