#!/bin/bash

# Group Sync Operator Monitoring Script
# Monitors the Group Sync Operator for group recreation and sync status
# Author: RBAC Automation Testing
# Version: 1.0

set -e

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

log_monitor() {
    echo -e "${CYAN}👀 $1${NC}"
}

# Script usage
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Group Sync Operator Monitoring Tool"
    echo ""
    echo "OPTIONS:"
    echo "  status, -s, --status     Show current Group Sync status (default)"
    echo "  monitor, -m, --monitor   Continuous monitoring mode"
    echo "  count, -c, --count       Show group counts only"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                       # Show current status"
    echo "  $0 status                # Show current status"
    echo "  $0 monitor               # Start continuous monitoring"
    echo "  $0 count                 # Show group counts"
    echo ""
    echo "MONITORING:"
    echo "  • Group Sync Operator status"
    echo "  • LDAP group count changes"
    echo "  • Sync schedule and timing"
    echo "  • LDAP server connectivity"
    echo ""
}

# Function to check Group Sync status
check_status() {
    log_info "👀 Monitoring Group Sync Operator - Current Status Check"
    log_info "========================================================"
    echo
    
    log_info "🔍 Group Sync Operator Status:"
    if oc get groupsync ldap-group-sync -n group-sync-operator &>/dev/null; then
        oc get groupsync ldap-group-sync -n group-sync-operator -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[0].type,SCHEDULE:.spec.schedule,LAST_SYNC:.status.lastSyncSuccessTime"
        
        # Get detailed status
        local status=$(oc get groupsync ldap-group-sync -n group-sync-operator -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
        local message=$(oc get groupsync ldap-group-sync -n group-sync-operator -o jsonpath='{.status.conditions[0].message}' 2>/dev/null)
        local last_sync=$(oc get groupsync ldap-group-sync -n group-sync-operator -o jsonpath='{.status.lastSyncSuccessTime}' 2>/dev/null)
        
        if [[ "$status" == "ReconcileSuccess" ]]; then
            log_success "Group Sync is working correctly"
        else
            log_warning "Group Sync status: $status"
            if [[ -n "$message" ]]; then
                echo "   Message: $message"
            fi
        fi
        
        if [[ -n "$last_sync" ]]; then
            echo "   Last successful sync: $last_sync"
        fi
    else
        log_error "Group Sync Operator not found or not accessible"
        return 1
    fi
    
    echo
    log_info "📊 Current LDAP Groups Count:"
    local group_count=$(oc get groups 2>/dev/null | grep app-ocp-rbac | wc -l)
    echo "   app-ocp-rbac-* groups: $group_count"
    
    if [ "$group_count" -gt 0 ]; then
        log_success "Groups are present and synced"
        echo
        log_info "🔍 Sample groups:"
        oc get groups | grep app-ocp-rbac | head -5 | sed 's/^/   /'
        if [ "$group_count" -gt 5 ]; then
            echo "   ... and $((group_count - 5)) more groups"
        fi
    else
        log_warning "No LDAP groups found - may have been deleted or not synced yet"
    fi
    
    echo
    log_info "🏃 LDAP Server Status:"
    if oc get pods -n ldap-testing | grep openldap | grep Running &>/dev/null; then
        log_success "LDAP server is running"
        oc get pods -n ldap-testing | grep openldap | sed 's/^/   /'
    else
        log_warning "LDAP server status unclear or not running"
        oc get pods -n ldap-testing | grep openldap | sed 's/^/   /' || echo "   No LDAP pods found"
    fi
}

# Function to show group counts only
show_counts() {
    local group_count=$(oc get groups 2>/dev/null | grep app-ocp-rbac | wc -l)
    local total_count=$(oc get groups 2>/dev/null | wc -l)
    
    echo "📊 Group Counts:"
    echo "   RBAC groups (app-ocp-rbac-*): $group_count"
    echo "   Total groups: $total_count"
    
    if [ "$group_count" -gt 0 ]; then
        echo
        echo "📋 RBAC group breakdown:"
        echo "   Demo groups: $(oc get groups 2>/dev/null | grep app-ocp-rbac-demo | wc -l)"
        echo "   Beta groups: $(oc get groups 2>/dev/null | grep app-ocp-rbac-beta | wc -l)"
        echo "   Jeff groups: $(oc get groups 2>/dev/null | grep app-ocp-rbac-jeff | wc -l)"
        echo "   Alpha groups: $(oc get groups 2>/dev/null | grep app-ocp-rbac-alpha | wc -l)"
        echo "   Other RBAC groups: $(oc get groups 2>/dev/null | grep app-ocp-rbac | grep -v -E "(demo|beta|jeff|alpha)" | wc -l)"
    fi
}

# Function for continuous monitoring
continuous_monitor() {
    log_monitor "🔄 Starting continuous Group Sync monitoring"
    log_monitor "=============================================="
    echo
    log_info "Monitoring for group recreation after deletion..."
    log_info "Group Sync schedule: Every 2 minutes (*/2 * * * *)"
    log_info "Press Ctrl+C to stop monitoring"
    echo
    
    local previous_count=0
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        local timestamp=$(date "+%H:%M:%S")
        local group_count=$(oc get groups 2>/dev/null | grep app-ocp-rbac | wc -l)
        local last_sync=$(oc get groupsync ldap-group-sync -n group-sync-operator -o jsonpath='{.status.lastSyncSuccessTime}' 2>/dev/null)
        local status=$(oc get groupsync ldap-group-sync -n group-sync-operator -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
        
        # Show monitoring line
        printf "[$timestamp] Iter:%2d | Groups:%2d | Status:%-15s | Last sync: %s\n" \
            "$iteration" "$group_count" "$status" "${last_sync#*T}"
        
        # If group count changed, show details
        if [ "$group_count" -ne "$previous_count" ]; then
            echo
            if [ "$group_count" -gt "$previous_count" ]; then
                log_success "🎉 GROUPS RECREATED! Found $group_count groups (was $previous_count)"
                if [ "$group_count" -gt 0 ]; then
                    echo "   Sample groups:"
                    oc get groups | grep app-ocp-rbac | head -5 | sed 's/^/   /'
                    if [ "$group_count" -gt 5 ]; then
                        echo "   ... and $((group_count - 5)) more groups"
                    fi
                fi
            elif [ "$group_count" -lt "$previous_count" ]; then
                log_warning "🗑️ Groups deleted! Count dropped from $previous_count to $group_count"
            fi
            echo
            previous_count=$group_count
        fi
        
        # If groups were found after being missing, we can stop
        if [ "$group_count" -gt 0 ] && [ "$previous_count" -eq 0 ]; then
            log_success "✅ Monitoring complete - groups successfully recreated!"
            break
        fi
        
        previous_count=$group_count
        sleep 15
    done
}

# Parse command line arguments
ACTION="status"  # Default action
while [[ $# -gt 0 ]]; do
    case $1 in
        status|-s|--status)
            ACTION="status"
            shift
            ;;
        monitor|-m|--monitor)
            ACTION="monitor"
            shift
            ;;
        count|-c|--count)
            ACTION="count"
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

# Main execution based on action
case "$ACTION" in
    "status")
        check_status
        ;;
    "monitor")
        continuous_monitor
        ;;
    "count")
        show_counts
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_help
        exit 1
        ;;
esac

echo
log_success "Group Sync monitoring completed! 🎯"