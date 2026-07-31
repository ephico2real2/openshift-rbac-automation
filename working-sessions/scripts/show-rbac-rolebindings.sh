#!/bin/bash

# RBAC RoleBindings Display Script
# Shows RoleBindings with their subjects (Groups/Users/ServiceAccounts) across namespaces
# Supports flexible namespace targeting: all, specific namespaces, or test namespaces
# Author: RBAC Automation
# Version: 1.0

set -e

# Define test namespaces (from setup-test-namespaces.sh)
TEST_NAMESPACES="demo-rnd demo-qa demo-uat beta-rnd beta-uat beta-prod jeff-rnd jeff-qa"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

log_header() {
    echo -e "${CYAN}🔍 $1${NC}"
}

# Script usage
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "RBAC RoleBindings Display Tool"
    echo ""
    echo "OPTIONS:"
    echo "  --target all             Show RoleBindings in all labeled namespaces (default)"
    echo "  --target test            Show RoleBindings in test namespaces only"
    echo "  --target NS1[,NS2,...]   Show RoleBindings in specific namespace(s)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                                    # Show all labeled namespaces"
    echo "  $0 --target all                      # Show all labeled namespaces"
    echo "  $0 --target test                     # Show test namespaces only"
    echo "  $0 --target demo-rnd                 # Show specific namespace"
    echo "  $0 --target demo-rnd,beta-prod       # Show multiple namespaces"
    echo ""
    echo "TEST NAMESPACES:"
    echo "  $TEST_NAMESPACES"
    echo ""
}

# Function to get namespaces based on target
get_target_namespaces() {
    local target="$1"
    
    case "$target" in
        "all"|"")
            # All namespaces with both required labels
            oc get ns -l 'company.net/mnemonic,company.net/app-environment' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
            ;;
        "test")
            # Predefined test namespaces
            echo "$TEST_NAMESPACES" | tr ' ' '\n'
            ;;
        *)
            # Comma-separated list of specific namespaces
            echo "$target" | tr ',' '\n'
            ;;
    esac
}

# Function to validate namespace exists
validate_namespace() {
    local ns="$1"
    if ! oc get namespace "$ns" >/dev/null 2>&1; then
        log_error "Namespace '$ns' does not exist"
        return 1
    fi
    return 0
}

# Function to show RoleBindings for a single namespace
show_namespace_rolebindings() {
    local ns="$1"
    
    if ! validate_namespace "$ns"; then
        return 1
    fi
    
    echo "=== Namespace: $ns ==="
    
    # Get namespace labels for context
    local mnemonic=$(oc get namespace "$ns" -o jsonpath='{.metadata.labels.company\.net/mnemonic}' 2>/dev/null || echo "")
    local environment=$(oc get namespace "$ns" -o jsonpath='{.metadata.labels.company\.net/app-environment}' 2>/dev/null || echo "")
    
    if [[ -n "$mnemonic" && -n "$environment" ]]; then
        echo "Labels: mnemonic=$mnemonic, environment=$environment"
    else
        echo "Labels: (no RBAC labels found)"
    fi
    
    # Get RoleBindings matching our pattern
    local rbs=$(oc get rolebindings -n "$ns" -o json 2>/dev/null | jq -r '.items[]? | select(.metadata.name|test("-(admin|developer|audit)-rb$")) | .metadata.name' | sort)
    
    if [ -n "$rbs" ]; then
        while IFS= read -r rb; do
            if [ -n "$rb" ]; then
                echo ""
                echo "RoleBinding: $rb"
                
                # Get role information
                local role=$(oc get rolebinding "$rb" -n "$ns" -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null || echo "Unknown")
                echo "  Role: $role"
                
                # Get creation timestamp
                local created=$(oc get rolebinding "$rb" -n "$ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")
                if [ -n "$created" ]; then
                    echo "  Created: $created"
                fi
                
                echo "  Subjects:"
                
                # Get subjects with detailed information
                oc get rolebinding "$rb" -n "$ns" -o json 2>/dev/null | jq -r '.subjects[]? | "    " + .kind + ": " + .name + (if .namespace then " (namespace: " + .namespace + ")" else "" end)' || echo "    (no subjects found)"
            fi
        done <<< "$rbs"
    else
        echo ""
        echo "  (no RBAC rolebindings found)"
    fi
    echo
}

# Main function
main() {
    local target="all"  # Default to all
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target)
                target="$2"
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
    
    log_header "Showing RoleBindings with their subjects (Groups/Users/ServiceAccounts)"
    
    case "$target" in
        "all"|"")
            log_info "Target: All namespaces with RBAC labels (company.net/mnemonic + company.net/app-environment)"
            ;;
        "test")
            log_info "Target: Test namespaces only"
            ;;
        *)
            log_info "Target: Specific namespace(s) - $target"
            ;;
    esac
    
    echo
    
    # Get target namespaces
    local namespaces=$(get_target_namespaces "$target")
    
    if [ -z "$namespaces" ]; then
        log_warning "No namespaces found for target: $target"
        exit 0
    fi
    
    # Show RoleBindings for each namespace
    local ns_count=0
    local rb_count=0
    
    while IFS= read -r ns; do
        if [ -n "$ns" ]; then
            show_namespace_rolebindings "$ns"
            ns_count=$((ns_count + 1))
            
            # Count RoleBindings in this namespace
            local ns_rb_count=$(oc get rolebindings -n "$ns" -o json 2>/dev/null | jq -r '.items[]? | select(.metadata.name|test("-(admin|developer|audit)-rb$")) | .metadata.name' | wc -l | tr -d ' ')
            rb_count=$((rb_count + ns_rb_count))
        fi
    done <<< "$namespaces"
    
    # Summary
    log_success "Summary: Found $rb_count RBAC RoleBindings across $ns_count namespaces"
}

# Run main function
main "$@"