#!/bin/bash

set -euo pipefail

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-github-actions-sa}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if PROJECT_ID is set
if [ -z "${PROJECT_ID}" ]; then
    print_error "PROJECT_ID is not set. Please set it using: export PROJECT_ID=your-project-id"
    exit 1
fi

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

print_info "Fixing permissions for service account: ${SERVICE_ACCOUNT_EMAIL}"
print_info "Project ID: ${PROJECT_ID}"

# Add Storage Admin role (needed for deploying from source)
print_info "Adding Storage Admin role..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/storage.admin" \
    --condition=None || print_info "Storage Admin role might already exist"

# Alternatively, you can use more granular permissions:
# print_info "Adding specific storage permissions..."
# gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
#     --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
#     --role="roles/storage.objectAdmin"

print_success "Permissions updated successfully!"

print_info "Current roles for ${SERVICE_ACCOUNT_EMAIL}:"
gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --format='table(bindings.role)' \
    --filter="bindings.members:${SERVICE_ACCOUNT_EMAIL}"

echo ""
print_info "The service account now has permission to:"
echo "  - Create and manage Cloud Storage buckets (needed for deploy from source)"
echo "  - Upload source code to Cloud Storage"
echo "  - Deploy services to Cloud Run"
echo ""
print_success "You can now retry the deployment!"