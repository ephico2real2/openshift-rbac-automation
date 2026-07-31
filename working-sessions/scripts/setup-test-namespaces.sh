#!/bin/bash

# RBAC Automation Test Namespace Setup Script
# Creates 8 namespaces across 3 teams (demo, beta, jeff) and 4 environments (rnd, qa, uat, prod)
# Adds required labels for NamespaceConfig to detect and create RoleBindings
# Author: RBAC Automation Testing
# Version: 1.0

set -e

# Script usage
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "RBAC Automation Test Namespace Management"
    echo ""
    echo "OPTIONS:"
    echo "  create, -c, --create     Create all test namespaces and labels (default)"
    echo "  delete, -d, --delete     Delete all test namespaces"
    echo "  verify, -v, --verify     Verify existing namespaces and labels"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                       # Create namespaces (default)"
    echo "  $0 create                # Create namespaces"
    echo "  $0 delete                # Delete all test namespaces"
    echo "  $0 verify                # Check existing setup"
    echo ""
}

# Parse command line arguments
ACTION="create"  # Default action
while [[ $# -gt 0 ]]; do
    case $1 in
        create|-c|--create)
            ACTION="create"
            shift
            ;;
        delete|-d|--delete)
            ACTION="delete"
            shift
            ;;
        verify|-v|--verify)
            ACTION="verify"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Define test namespaces array
TEST_NAMESPACES=("demo-rnd" "demo-qa" "demo-uat" "beta-rnd" "beta-uat" "beta-prod" "jeff-rnd" "jeff-qa")

# Function to create namespaces
create_namespaces() {

log_info "🚀 Creating 8 test namespaces for RBAC automation testing"
log_info "======================================================="
echo
log_info "📊 Using available 4-letter mnemonics: beta, demo, jeff"
log_info "📊 Using environments: rnd, qa, uat, prod"
echo

log_info "1️⃣ Creating DEMO team namespaces..."
echo "   Creating demo-rnd (Research & Development)"
oc new-project demo-rnd --display-name="Demo Research & Development" 2>/dev/null || log_warning "demo-rnd project might already exist"

echo "   Creating demo-qa (Quality Assurance)" 
oc new-project demo-qa --display-name="Demo Quality Assurance" 2>/dev/null || log_warning "demo-qa project might already exist"

echo "   Creating demo-uat (User Acceptance Testing)"
oc new-project demo-uat --display-name="Demo User Acceptance Testing" 2>/dev/null || log_warning "demo-uat project might already exist"

echo
log_info "2️⃣ Creating BETA team namespaces..."
echo "   Creating beta-rnd (Research & Development)"
oc new-project beta-rnd --display-name="Beta Research & Development" 2>/dev/null || log_warning "beta-rnd project might already exist"

echo "   Creating beta-uat (User Acceptance Testing)" 
oc new-project beta-uat --display-name="Beta User Acceptance Testing" 2>/dev/null || log_warning "beta-uat project might already exist"

echo "   Creating beta-prod (Production)"
oc new-project beta-prod --display-name="Beta Production" 2>/dev/null || log_warning "beta-prod project might already exist"

echo
log_info "3️⃣ Creating JEFF team namespaces..."
echo "   Creating jeff-rnd (Research & Development)"
oc new-project jeff-rnd --display-name="Jeff Research & Development" 2>/dev/null || log_warning "jeff-rnd project might already exist"

echo "   Creating jeff-qa (Quality Assurance)"
oc new-project jeff-qa --display-name="Jeff Quality Assurance" 2>/dev/null || log_warning "jeff-qa project might already exist"

echo
log_success "All namespaces created successfully!"

echo
log_info "🏷️ Adding required labels to all 8 namespaces for RBAC automation"
log_info "================================================================="
echo

log_info "1️⃣ Labeling DEMO team namespaces..."
echo "   demo-rnd (Research & Development - Full access expected)"
oc label namespace demo-rnd company.net/mnemonic=demo --overwrite
oc label namespace demo-rnd company.net/app-environment=rnd --overwrite

echo "   demo-qa (Quality Assurance - Full access expected)"
oc label namespace demo-qa company.net/mnemonic=demo --overwrite  
oc label namespace demo-qa company.net/app-environment=qa --overwrite

echo "   demo-uat (User Acceptance Testing - Full access expected)"
oc label namespace demo-uat company.net/mnemonic=demo --overwrite
oc label namespace demo-uat company.net/app-environment=uat --overwrite

echo
log_info "2️⃣ Labeling BETA team namespaces..."
echo "   beta-rnd (Research & Development - Full access expected)"
oc label namespace beta-rnd company.net/mnemonic=beta --overwrite
oc label namespace beta-rnd company.net/app-environment=rnd --overwrite

echo "   beta-uat (User Acceptance Testing - Full access expected)"
oc label namespace beta-uat company.net/mnemonic=beta --overwrite
oc label namespace beta-uat company.net/app-environment=uat --overwrite

echo "   beta-prod (Production - AUDIT ONLY expected)"
oc label namespace beta-prod company.net/mnemonic=beta --overwrite
oc label namespace beta-prod company.net/app-environment=prod --overwrite

echo
log_info "3️⃣ Labeling JEFF team namespaces..."
echo "   jeff-rnd (Research & Development - Full access expected)"
oc label namespace jeff-rnd company.net/mnemonic=jeff --overwrite
oc label namespace jeff-rnd company.net/app-environment=rnd --overwrite

echo "   jeff-qa (Quality Assurance - Full access expected)"
oc label namespace jeff-qa company.net/mnemonic=jeff --overwrite
oc label namespace jeff-qa company.net/app-environment=qa --overwrite

echo
log_success "All labels applied successfully!"

echo
log_info "✅ VERIFICATION: Checking all namespace labels..."
log_info "================================================="
for ns in demo-rnd demo-qa demo-uat beta-rnd beta-uat beta-prod jeff-rnd jeff-qa; do
    echo "📋 $ns:"
    oc get namespace $ns -o jsonpath='{.metadata.labels}' | jq -r 'to_entries[] | select(.key | contains("company.net")) | "  \(.key): \(.value)"' 2>/dev/null || {
        echo "  Labels: $(oc get namespace $ns --show-labels | grep -o 'company.net[^,]*' | tr '\n' ' ')"
    }
done

echo
log_info "🔍 ADDITIONAL VERIFICATIONS:"
log_info "============================"

echo
log_info "📊 Available LDAP groups that will be used:"
echo "Demo team groups:"
oc get groups | grep "app-ocp-rbac-demo-ns-" | sed 's/^/  /'

echo "Beta team groups:"
oc get groups | grep "app-ocp-rbac-beta-ns-" | sed 's/^/  /'

echo "Jeff team groups:"
oc get groups | grep "app-ocp-rbac-jeff-ns-" | sed 's/^/  /'

echo
log_success "🎉 NAMESPACE SETUP COMPLETE!"
log_success "============================"
echo
log_info "📊 Created 8 namespaces across 3 teams and 4 environments:"
echo
log_info "🟢 FULL ACCESS ENVIRONMENTS (Admin + Developer + Audit):"
echo "   demo-rnd   → demo + rnd  → app-ocp-rbac-demo-ns-* groups"
echo "   demo-qa    → demo + qa   → app-ocp-rbac-demo-ns-* groups" 
echo "   demo-uat   → demo + uat  → app-ocp-rbac-demo-ns-* groups"
echo "   beta-rnd   → beta + rnd  → app-ocp-rbac-beta-ns-* groups"
echo "   beta-uat   → beta + uat  → app-ocp-rbac-beta-ns-* groups"
echo "   jeff-rnd   → jeff + rnd  → app-ocp-rbac-jeff-ns-* groups"
echo "   jeff-qa    → jeff + qa   → app-ocp-rbac-jeff-ns-* groups"
echo
log_warning "🔒 RESTRICTED ENVIRONMENTS (Audit Only):"
echo "   beta-prod  → beta + prod → app-ocp-rbac-beta-ns-audit group only"
echo
log_success "🚀 Ready to deploy NamespaceConfig!"
log_info "When deployed, the NamespaceConfig will:"
log_info "• Detect all 8 labeled namespaces"
log_info "• Create RoleBindings based on environment restrictions"  
log_info "• Link to existing LDAP groups automatically"
echo
log_info "Expected users who will get access:"
log_info "• Demo team: john.doe, jane.smith, bob.wilson, sarah.jones"
log_info "• Beta team: jane.smith, alice.cooper, bob.wilson"
log_info "• Jeff team: jeff"

echo
log_info "🔧 Next Steps:"
log_info "1. Deploy NamespaceConfigs:"
log_info "   oc apply -f policies/nonprod-namespaceconfig-rbac.yaml"
log_info "   oc apply -f policies/prod-namespaceconfig-rbac.yaml"
log_info "2. Verify RoleBindings: oc get rolebindings -n <namespace-name>"
log_info "3. Check access: oc auth can-i --list --as=system:serviceaccount:<namespace>:default"

echo
log_success "Setup completed successfully! 🎯"
}

# Function to delete all test namespaces
delete_namespaces() {
    log_warning "🗑️ Deleting all RBAC automation test namespaces"
    log_warning "============================================="
    echo
    
    log_warning "⚠️ WARNING: This will permanently delete the following namespaces:"
    for ns in "${TEST_NAMESPACES[@]}"; do
        if oc get namespace "$ns" &>/dev/null; then
            echo "  • $ns (exists)"
        else
            echo "  • $ns (not found)"
        fi
    done
    
    echo
    read -p "Are you sure you want to delete all these namespaces? (yes/NO): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo
    log_info "🗑️ Deleting namespaces..."
    for ns in "${TEST_NAMESPACES[@]}"; do
        if oc get namespace "$ns" &>/dev/null; then
            echo "   Deleting $ns..."
            oc delete project "$ns" --ignore-not-found=true
            log_success "Deleted: $ns"
        else
            log_warning "Not found: $ns (skipping)"
        fi
    done
    
    echo
    log_success "🎉 All test namespaces deleted successfully!"
    log_info "Note: It may take a few moments for namespaces to be completely removed"
}

# Function to verify existing setup
verify_namespaces() {
    log_info "🔍 Verifying RBAC automation test namespace setup"
    log_info "==============================================="
    echo
    
    log_info "📊 Checking namespace existence and labels:"
    local found_count=0
    local labeled_count=0
    
    for ns in "${TEST_NAMESPACES[@]}"; do
        if oc get namespace "$ns" &>/dev/null; then
            echo "✅ $ns: exists"
            found_count=$((found_count + 1))
            
            # Check labels
            local mnemonic=$(oc get namespace "$ns" -o jsonpath='{.metadata.labels.company\.net/mnemonic}' 2>/dev/null || echo "")
            local environment=$(oc get namespace "$ns" -o jsonpath='{.metadata.labels.company\.net/app-environment}' 2>/dev/null || echo "")
            
            if [[ -n "$mnemonic" && -n "$environment" ]]; then
                echo "   Labels: mnemonic=$mnemonic, environment=$environment"
                labeled_count=$((labeled_count + 1))
            else
                echo "   ⚠️ Missing required labels"
            fi
        else
            echo "❌ $ns: not found"
        fi
    done
    
    echo
    log_info "📈 Summary:"
    log_info "• Namespaces found: $found_count/${#TEST_NAMESPACES[@]}"
    log_info "• Properly labeled: $labeled_count/${#TEST_NAMESPACES[@]}"
    
    if [[ $found_count -eq ${#TEST_NAMESPACES[@]} && $labeled_count -eq ${#TEST_NAMESPACES[@]} ]]; then
        log_success "🎉 All test namespaces are properly configured!"
    elif [[ $found_count -eq 0 ]]; then
        log_warning "No test namespaces found. Run '$0 create' to set them up."
    else
        log_warning "Some namespaces are missing or not properly labeled."
        log_info "Run '$0 create' to fix the setup."
    fi
    
    if [[ $found_count -gt 0 ]]; then
        echo
        log_info "🔍 Checking related LDAP groups:"
        echo "Demo team groups:"
        oc get groups | grep "app-ocp-rbac-demo-ns-" | sed 's/^/  /' || echo "  No demo groups found"
        
        echo "Beta team groups:"
        oc get groups | grep "app-ocp-rbac-beta-ns-" | sed 's/^/  /' || echo "  No beta groups found"
        
        echo "Jeff team groups:"
        oc get groups | grep "app-ocp-rbac-jeff-ns-" | sed 's/^/  /' || echo "  No jeff groups found"
    fi
}

# Main execution based on action
case "$ACTION" in
    "create")
        create_namespaces
        ;;
    "delete")
        delete_namespaces
        ;;
    "verify")
        verify_namespaces
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_help
        exit 1
        ;;
esac
