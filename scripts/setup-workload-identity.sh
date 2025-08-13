#!/bin/bash

set -euo pipefail

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
GITHUB_ORG="${GITHUB_ORG:-ngs}"
GITHUB_REPO="${GITHUB_REPO:-jplaw2epub-web-api}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-github-actions-sa}"
POOL_NAME="${POOL_NAME:-github-pool}"
PROVIDER_NAME="${PROVIDER_NAME:-github-provider}"

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if PROJECT_ID is set
if [ -z "${PROJECT_ID}" ]; then
    print_error "PROJECT_ID is not set. Please set it using: export PROJECT_ID=your-project-id"
    exit 1
fi

print_info "Setting up Workload Identity Federation for GitHub Actions"
print_info "Project ID: ${PROJECT_ID}"
print_info "GitHub Repository: ${GITHUB_ORG}/${GITHUB_REPO}"

# Enable required APIs
print_info "Enabling required APIs..."
gcloud services enable iamcredentials.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    --project="${PROJECT_ID}"

# Create Workload Identity Pool
print_info "Creating Workload Identity Pool..."
gcloud iam workload-identity-pools create "${POOL_NAME}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --description="Workload Identity Pool for GitHub Actions" || print_warning "Pool might already exist"

# Get Workload Identity Pool ID
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe "${POOL_NAME}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --format="value(name)")

print_info "Workload Identity Pool ID: ${WORKLOAD_IDENTITY_POOL_ID}"

# Create Workload Identity Provider
print_info "Creating Workload Identity Provider..."
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --display-name="GitHub Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
    --issuer-uri="https://token.actions.githubusercontent.com" || print_warning "Provider might already exist"

# Create Service Account
print_info "Creating Service Account..."
gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions Service Account" \
    --description="Service account for GitHub Actions CI/CD" || print_warning "Service account might already exist"

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
print_info "Service Account Email: ${SERVICE_ACCOUNT_EMAIL}"

# Grant permissions to the service account
print_info "Granting permissions to the service account..."

# Add Cloud Run Developer role
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/run.developer"

# Add Service Account User role
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/iam.serviceAccountUser"

# Add Storage Admin role (needed for deploying from source)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/storage.admin"

# Add Artifact Registry Writer role (for pushing Docker images)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/artifactregistry.writer"

# Add Cloud Build Editor role (if using Cloud Build)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/cloudbuild.builds.editor"

# Add Service Usage Consumer role (needed for Cloud Build)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/serviceusage.serviceUsageConsumer"

# Bind service account to Workload Identity Pool
print_info "Binding service account to Workload Identity Pool..."
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

# Get Workload Identity Provider resource name
WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="value(name)")

print_info "Workload Identity Provider: ${WORKLOAD_IDENTITY_PROVIDER}"

# Output GitHub Actions configuration
print_info "Setup completed successfully!"
echo ""
print_info "Add the following secrets to your GitHub repository:"
echo ""
echo "WIF_PROVIDER: ${WORKLOAD_IDENTITY_PROVIDER}"
echo "WIF_SERVICE_ACCOUNT: ${SERVICE_ACCOUNT_EMAIL}"
echo ""
print_info "Add the following to your GitHub Actions workflow:"
echo ""
cat << EOF
      - id: 'auth'
        name: 'Authenticate to Google Cloud'
        uses: 'google-github-actions/auth@v2'
        with:
          workload_identity_provider: '\${{ secrets.WIF_PROVIDER }}'
          service_account: '\${{ secrets.WIF_SERVICE_ACCOUNT }}'

      - name: 'Set up Cloud SDK'
        uses: 'google-github-actions/setup-gcloud@v2'
EOF
echo ""
print_info "You can also set PROJECT_ID as a GitHub secret: ${PROJECT_ID}"