#!/bin/bash

set -euo pipefail

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
PROJECT_NUMBER="${PROJECT_NUMBER:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if PROJECT_ID is set
if [ -z "${PROJECT_ID}" ]; then
    print_error "PROJECT_ID is not set. Please set it using: export PROJECT_ID=your-project-id"
    exit 1
fi

print_info "Fixing Cloud Build and Cloud Run permissions"
print_info "Project ID: ${PROJECT_ID}"

# Get project number if not provided
if [ -z "${PROJECT_NUMBER}" ]; then
    print_info "Getting project number..."
    PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
    print_info "Project Number: ${PROJECT_NUMBER}"
fi

# Enable required APIs
print_info "Enabling required APIs..."
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    containerregistry.googleapis.com \
    storage.googleapis.com \
    serviceusage.googleapis.com \
    iam.googleapis.com \
    --project="${PROJECT_ID}"

# Define service accounts
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
GITHUB_ACTIONS_SA="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"

print_info "Service accounts:"
echo "  Cloud Build: ${CLOUD_BUILD_SA}"
echo "  Compute Engine: ${COMPUTE_SA}"
echo "  GitHub Actions: ${GITHUB_ACTIONS_SA}"
echo ""

# Grant permissions to Cloud Build service account
print_info "Granting permissions to Cloud Build service account..."

# Cloud Run Admin (to deploy services)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/run.admin" \
    --condition=None || print_warning "Cloud Run Admin role might already exist"

# Service Account User (to act as service account)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None || print_warning "Service Account User role might already exist"

# Storage Admin (to create and manage buckets)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/storage.admin" \
    --condition=None || print_warning "Storage Admin role might already exist"

# Artifact Registry Writer
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/artifactregistry.writer" \
    --condition=None || print_warning "Artifact Registry Writer role might already exist"

# Grant permissions to Compute Engine default service account
print_info "Granting permissions to Compute Engine default service account..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/cloudbuild.builds.builder" \
    --condition=None || print_warning "Cloud Build Builder role might already exist"

# Grant Service Usage Consumer to GitHub Actions service account
print_info "Granting Service Usage Consumer to GitHub Actions service account..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${GITHUB_ACTIONS_SA}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None || print_warning "Service Usage Consumer role might already exist"

# Also grant Cloud Build Editor role to GitHub Actions SA
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${GITHUB_ACTIONS_SA}" \
    --role="roles/cloudbuild.builds.editor" \
    --condition=None || print_warning "Cloud Build Editor role might already exist"

# Grant logging permissions
print_info "Granting logging permissions..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/logging.logWriter" \
    --condition=None || print_warning "Logging Writer role might already exist"

print_success "Permissions have been updated!"

echo ""
print_info "Summary of permissions granted:"
echo ""
echo "Cloud Build Service Account (${CLOUD_BUILD_SA}):"
echo "  ✓ Cloud Run Admin"
echo "  ✓ Service Account User"
echo "  ✓ Storage Admin"
echo "  ✓ Artifact Registry Writer"
echo "  ✓ Logging Writer"
echo ""
echo "GitHub Actions Service Account (${GITHUB_ACTIONS_SA}):"
echo "  ✓ Service Usage Consumer"
echo "  ✓ Cloud Build Editor"
echo ""
echo "Compute Engine Service Account (${COMPUTE_SA}):"
echo "  ✓ Cloud Build Builder"
echo ""

print_info "Verifying permissions (this may take a moment)..."
sleep 5

# Check if Cloud Build SA has required permissions
if gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --format="value(bindings.role)" \
    --filter="bindings.members:${CLOUD_BUILD_SA}" | grep -q "roles/run.admin"; then
    print_success "Cloud Build service account has Cloud Run Admin role"
else
    print_warning "Cloud Build service account might not have all required roles yet"
fi

echo ""
print_info "Next steps:"
echo "  1. Wait 2-3 minutes for permissions to propagate"
echo "  2. Retry the deployment"
echo ""
print_success "Setup complete! You can now deploy from source using Cloud Run."