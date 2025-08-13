#!/bin/bash

set -euo pipefail

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
GITHUB_ORG="${GITHUB_ORG:-ngs}"
GITHUB_REPO="${GITHUB_REPO:-jplaw2epub-web-api}"
REGION="${REGION:-asia-northeast1}"

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

print_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check if PROJECT_ID is set
if [ -z "${PROJECT_ID}" ]; then
    print_error "PROJECT_ID is not set. Please set it using: export PROJECT_ID=your-project-id"
    exit 1
fi

print_info "Complete setup for jplaw2epub Web API deployment"
print_info "Project ID: ${PROJECT_ID}"
print_info "GitHub: ${GITHUB_ORG}/${GITHUB_REPO}"
print_info "Region: ${REGION}"

# Get project number
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
print_info "Project Number: ${PROJECT_NUMBER}"

# Step 1: Enable APIs
print_step "Step 1: Enabling Required APIs"

gcloud services enable \
    iamcredentials.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    containerregistry.googleapis.com \
    storage.googleapis.com \
    serviceusage.googleapis.com \
    logging.googleapis.com \
    --project="${PROJECT_ID}"

print_success "APIs enabled"

# Step 2: Setup Workload Identity Federation
print_step "Step 2: Setting up Workload Identity Federation"

# Run the WIF setup script
if [ -f "scripts/setup-workload-identity.sh" ]; then
    bash scripts/setup-workload-identity.sh
else
    print_warning "setup-workload-identity.sh not found, running inline setup..."
    
    # Create Workload Identity Pool
    gcloud iam workload-identity-pools create "github-pool" \
        --project="${PROJECT_ID}" \
        --location="global" \
        --display-name="GitHub Actions Pool" || true
    
    # Create provider
    gcloud iam workload-identity-pools providers create-oidc "github-provider" \
        --project="${PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool="github-pool" \
        --display-name="GitHub Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
        --issuer-uri="https://token.actions.githubusercontent.com" || true
fi

# Step 3: Fix Cloud Build permissions
print_step "Step 3: Configuring Cloud Build Permissions"

CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
GITHUB_ACTIONS_SA="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant permissions to Cloud Build service account
print_info "Configuring Cloud Build service account..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/run.admin" \
    --condition=None || true

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None || true

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/storage.admin" \
    --condition=None || true

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/artifactregistry.writer" \
    --condition=None || true

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/logging.logWriter" \
    --condition=None || true

# Grant permissions to Compute Engine default service account
print_info "Configuring Compute Engine service account..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/cloudbuild.builds.builder" \
    --condition=None || true

# Additional permissions for GitHub Actions SA
print_info "Adding additional permissions to GitHub Actions service account..."

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${GITHUB_ACTIONS_SA}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None || true

print_success "Cloud Build permissions configured"

# Step 4: Setup Artifact Registry
print_step "Step 4: Setting up Artifact Registry"

if [ -f "scripts/setup-artifact-registry.sh" ]; then
    bash scripts/setup-artifact-registry.sh
else
    print_info "Creating Artifact Registry repository..."
    gcloud artifacts repositories create "cloud-run-source-deploy" \
        --repository-format="docker" \
        --location="${REGION}" \
        --description="Docker repository for Cloud Run" \
        --project="${PROJECT_ID}" || true
fi

print_success "Artifact Registry configured"

# Step 5: Get configuration values
print_step "Step 5: Configuration Summary"

WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe "github-pool" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --format="value(name)")

WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools providers describe "github-provider" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --format="value(name)")

echo ""
print_success "Setup completed successfully!"
echo ""
print_info "Add these secrets to your GitHub repository:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GitHub Secrets Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "PROJECT_ID:"
echo "${PROJECT_ID}"
echo ""
echo "WIF_PROVIDER:"
echo "${WORKLOAD_IDENTITY_PROVIDER}"
echo ""
echo "WIF_SERVICE_ACCOUNT:"
echo "${GITHUB_ACTIONS_SA}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "Next steps:"
echo "  1. Go to https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/settings/secrets/actions"
echo "  2. Add the three secrets shown above"
echo "  3. Wait 2-3 minutes for permissions to propagate"
echo "  4. Push to main/master branch to trigger deployment"
echo ""
print_success "All done! Your project is ready for deployment."