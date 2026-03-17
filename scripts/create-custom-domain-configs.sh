#!/bin/bash

# Script to create custom domain versions of NamespaceConfig files
# Usage: ./create-custom-domain-configs.sh <new-domain>
# Example: ./create-custom-domain-configs.sh pnc.net

set -euo pipefail

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if domain argument is provided
if [ $# -eq 0 ]; then
    log_error "No domain provided"
    echo "Usage: $0 <new-domain>"
    echo "Example: $0 pnc.net"
    exit 1
fi

NEW_DOMAIN="$1"
ORIGINAL_DOMAIN="company.net"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="$(dirname "$SCRIPT_DIR")/policies"

log_info "Creating custom domain NamespaceConfig files"
log_info "Original domain: $ORIGINAL_DOMAIN"
log_info "New domain: $NEW_DOMAIN"
log_info "Policies directory: $POLICIES_DIR"

# Check if policies directory exists
if [ ! -d "$POLICIES_DIR" ]; then
    log_error "Policies directory not found: $POLICIES_DIR"
    exit 1
fi

# Change to policies directory
cd "$POLICIES_DIR"

# Array of NamespaceConfig files to process
NAMESPACE_CONFIG_FILES=(
    "nonprod-namespaceconfig-rbac.yaml"
    "prod-namespaceconfig-rbac.yaml"
)

# Counter for created files
created_count=0

# Process each file
for file in "${NAMESPACE_CONFIG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_warn "File not found: $file (skipping)"
        continue
    fi
    
    # Output file with custom domain prefix
    output_file="${NEW_DOMAIN}-${file}"
    
    log_info "Processing: $file"
    
    # Replace domain in file and create new file
    sed "s/${ORIGINAL_DOMAIN}/${NEW_DOMAIN}/g" "$file" > "$output_file"
    
    if [ -f "$output_file" ]; then
        log_info "Created: $output_file"
        ((created_count++))
    else
        log_error "Failed to create: $output_file"
    fi
done

echo ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Summary: Created $created_count custom domain files"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# List created files
if [ $created_count -gt 0 ]; then
    echo ""
    log_info "Created files:"
    ls -lh "${NEW_DOMAIN}"-*.yaml 2>/dev/null || true
    
    echo ""
    log_info "Verification:"
    log_info "Run this command to verify the replacement:"
    echo "  grep -n \"${NEW_DOMAIN}\" ${NEW_DOMAIN}-nonprod-namespaceconfig-rbac.yaml | head -10"
    
    echo ""
    log_info "Deployment:"
    log_info "To deploy these configs to your cluster:"
    echo "  oc apply -f ${NEW_DOMAIN}-nonprod-namespaceconfig-rbac.yaml"
    echo "  oc apply -f ${NEW_DOMAIN}-prod-namespaceconfig-rbac.yaml"
    
    echo ""
    log_info "Note: Make sure your namespaces use labels with the new domain:"
    echo "  ${NEW_DOMAIN}/mnemonic=<mnemonic>"
    echo "  ${NEW_DOMAIN}/app-environment=<environment>"
fi

echo ""
log_info "Done! ✅"
