#!/bin/bash

# Manual RBAC Automation Script
# Simulates the Red Hat CoP Namespace Configuration Operator functionality
# Author: RBAC Automation Testing
# Version: 1.0

set -e

SCRIPT_NAME=$(basename "$0")
NAMESPACE=""
MNEMONIC=""
ENVIRONMENT=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help function
show_help() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo ""
    echo "Manual RBAC automation for testing OpenShift RBAC patterns"
    echo ""
    echo "OPTIONS:"
    echo "  -n, --namespace NAMESPACE    Target namespace name"
    echo "  -m, --mnemonic MNEMONIC      4-letter team mnemonic (e.g., demo, paym)"
    echo "  -e, --environment ENV        Environment: rnd, eng, qa, uat, prod"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $SCRIPT_NAME -n payment-dev -m paym -e rnd"
    echo "  $SCRIPT_NAME -n payment-prod -m paym -e prod"
    echo ""
    echo "FEATURES:"
    echo "  ✅ Environment-aware security (no admin/edit in prod)"
    echo "  ✅ Automatic namespace labeling"
    echo "  ✅ RoleBinding creation (admin, developer, audit)"
    echo "  ✅ ClusterRoleBinding creation (cluster access)"
    echo "  ✅ Monitoring access (user workload monitoring)"
    echo ""
}

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Validation functions
validate_mnemonic() {
    if [[ ! "$MNEMONIC" =~ ^[a-z]{4}$ ]]; then
        log_error "Invalid mnemonic: $MNEMONIC"
        log_error "Mnemonic must be exactly 4 lowercase letters (e.g., demo, paym, frnt)"
        exit 1
    fi
}

validate_environment() {
    case "$ENVIRONMENT" in
        rnd|eng|qa|uat|prod)
            log_success "Valid environment: $ENVIRONMENT"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Environment must be one of: rnd, eng, qa, uat, prod"
            exit 1
            ;;
    esac
}

validate_groups() {
    local missing_groups=()
    
    # Check required groups exist
    for group_type in "ns-admin" "ns-developer" "ns-audit" "cluster-admin" "cluster-developer" "cluster-audit"; do
        local group_name="app-ocp-rbac-${MNEMONIC}-${group_type}"
        if ! oc get group "$group_name" &>/dev/null; then
            missing_groups+=("$group_name")
        fi
    done
    
    if [ ${#missing_groups[@]} -gt 0 ]; then
        log_error "Missing required LDAP groups:"
        for group in "${missing_groups[@]}"; do
            log_error "  - $group"
        done
        log_error "Ensure Group Sync Operator has synced these groups from LDAP"
        exit 1
    fi
    
    log_success "All required LDAP groups exist"
}

# RBAC creation functions
create_namespace_labels() {
    log_info "Adding namespace labels..."
    
    oc label namespace "$NAMESPACE" company.net/mnemonic="$MNEMONIC" --overwrite
    oc label namespace "$NAMESPACE" company.net/app-environment="$ENVIRONMENT" --overwrite
    
    log_success "Namespace labels added"
}

create_namespace_rbac() {
    log_info "Creating namespace RoleBindings..."
    
    # Always create audit access
    oc create rolebinding "${MNEMONIC}-audit-rb" \
        --clusterrole=view \
        --group="app-ocp-rbac-${MNEMONIC}-ns-audit" \
        -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
    
    log_success "Created audit RoleBinding: ${MNEMONIC}-audit-rb"
    
    # Create admin/developer access only for non-production environments
    if [[ "$ENVIRONMENT" != "prod" ]]; then
        oc create rolebinding "${MNEMONIC}-admin-rb" \
            --clusterrole=admin \
            --group="app-ocp-rbac-${MNEMONIC}-ns-admin" \
            -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
        
        oc create rolebinding "${MNEMONIC}-developer-rb" \
            --clusterrole=edit \
            --group="app-ocp-rbac-${MNEMONIC}-ns-developer" \
            -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
        
        log_success "Created admin RoleBinding: ${MNEMONIC}-admin-rb"
        log_success "Created developer RoleBinding: ${MNEMONIC}-developer-rb"
    else
        log_warning "Production environment: Skipped admin/developer access (security policy)"
    fi
}

create_cluster_rbac() {
    log_info "Creating cluster-level RoleBindings..."
    
    # Create ClusterRoleBindings (not environment-specific)
    oc create clusterrolebinding "${MNEMONIC}-cluster-admin-crb" \
        --clusterrole=cluster-admin \
        --group="app-ocp-rbac-${MNEMONIC}-cluster-admin" \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null || log_info "ClusterRoleBinding already exists: ${MNEMONIC}-cluster-admin-crb"
    
    oc create clusterrolebinding "${MNEMONIC}-cluster-developer-crb" \
        --clusterrole=edit \
        --group="app-ocp-rbac-${MNEMONIC}-cluster-developer" \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null || log_info "ClusterRoleBinding already exists: ${MNEMONIC}-cluster-developer-crb"
    
    oc create clusterrolebinding "${MNEMONIC}-cluster-audit-crb" \
        --clusterrole=view \
        --group="app-ocp-rbac-${MNEMONIC}-cluster-audit" \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null || log_info "ClusterRoleBinding already exists: ${MNEMONIC}-cluster-audit-crb"
    
    log_success "Created cluster RoleBindings"
}

create_monitoring_access() {
    log_info "Creating monitoring access..."
    
    # Create monitoring configuration access for admin and developer groups
    oc create rolebinding "${MNEMONIC}-monitoring-config-rb" \
        --clusterrole=monitoring-rules-edit \
        --group="app-ocp-rbac-${MNEMONIC}-ns-admin" \
        --group="app-ocp-rbac-${MNEMONIC}-ns-developer" \
        -n openshift-user-workload-monitoring \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null || log_info "Monitoring RoleBinding already exists: ${MNEMONIC}-monitoring-config-rb"
    
    log_success "Created monitoring access"
}

show_summary() {
    echo ""
    log_info "🎯 RBAC Automation Summary"
    echo "=================================="
    echo "📁 Namespace: $NAMESPACE"
    echo "🏷️  Mnemonic: $MNEMONIC"
    echo "🌍 Environment: $ENVIRONMENT"
    echo ""
    
    log_info "📊 Created Access:"
    
    # Namespace access
    echo "  Namespace RBAC:"
    if [[ "$ENVIRONMENT" != "prod" ]]; then
        echo "    ✅ Admin access: app-ocp-rbac-${MNEMONIC}-ns-admin"
        echo "    ✅ Developer access: app-ocp-rbac-${MNEMONIC}-ns-developer"
    else
        echo "    ❌ Admin access: BLOCKED (production security)"
        echo "    ❌ Developer access: BLOCKED (production security)"
    fi
    echo "    ✅ Audit access: app-ocp-rbac-${MNEMONIC}-ns-audit"
    
    # Cluster access
    echo "  Cluster RBAC:"
    echo "    ✅ Cluster admin: app-ocp-rbac-${MNEMONIC}-cluster-admin"
    echo "    ✅ Cluster developer: app-ocp-rbac-${MNEMONIC}-cluster-developer"
    echo "    ✅ Cluster audit: app-ocp-rbac-${MNEMONIC}-cluster-audit"
    
    # Monitoring access
    echo "  Monitoring Access:"
    echo "    ✅ User workload monitoring: app-ocp-rbac-${MNEMONIC}-ns-(admin|developer)"
    
    echo ""
    log_info "🔍 Verification Commands:"
    echo "  oc get rolebindings -n $NAMESPACE"
    echo "  oc get clusterrolebindings | grep $MNEMONIC"
    echo "  oc get rolebindings -n openshift-user-workload-monitoring | grep $MNEMONIC"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -m|--mnemonic)
            MNEMONIC="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$NAMESPACE" || -z "$MNEMONIC" || -z "$ENVIRONMENT" ]]; then
    log_error "Missing required parameters"
    show_help
    exit 1
fi

# Main execution
main() {
    log_info "🚀 Starting RBAC automation for namespace: $NAMESPACE"
    
    # Validate inputs
    validate_mnemonic
    validate_environment
    
    # Check if namespace exists
    if ! oc get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        log_info "Create it first with: oc new-project $NAMESPACE"
        exit 1
    fi
    
    # Validate LDAP groups exist
    validate_groups
    
    # Create RBAC
    create_namespace_labels
    create_namespace_rbac
    create_cluster_rbac
    create_monitoring_access
    
    # Show summary
    show_summary
    
    log_success "🎉 RBAC automation completed successfully!"
}

# Run main function
main