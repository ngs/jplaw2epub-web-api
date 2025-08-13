#!/bin/bash

set -euo pipefail

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-asia-northeast1}"
REPOSITORY_NAME="${REPOSITORY_NAME:-cloud-run-source-deploy}"
REPOSITORY_FORMAT="${REPOSITORY_FORMAT:-docker}"
DESCRIPTION="${DESCRIPTION:-Docker repository for Cloud Run deployments}"

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

print_info "Setting up Artifact Registry for Cloud Run deployments"
print_info "Project ID: ${PROJECT_ID}"
print_info "Region: ${REGION}"
print_info "Repository: ${REPOSITORY_NAME}"
echo ""

# Set the project
gcloud config set project "${PROJECT_ID}"

# Enable Artifact Registry API
print_info "Enabling Artifact Registry API..."
gcloud services enable artifactregistry.googleapis.com --project="${PROJECT_ID}"

# Check if repository already exists
print_info "Checking if repository exists..."
if gcloud artifacts repositories describe "${REPOSITORY_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" &>/dev/null; then
    print_warning "Repository '${REPOSITORY_NAME}' already exists in ${REGION}"
    print_info "Skipping repository creation"
else
    # Create Artifact Registry repository
    print_info "Creating Artifact Registry repository..."
    gcloud artifacts repositories create "${REPOSITORY_NAME}" \
        --repository-format="${REPOSITORY_FORMAT}" \
        --location="${REGION}" \
        --description="${DESCRIPTION}" \
        --project="${PROJECT_ID}"
    
    print_success "Repository created successfully!"
fi

# Configure Docker authentication
print_info "Configuring Docker authentication for ${REGION}..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Display repository details
echo ""
print_info "Repository Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Repository URL: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
echo "  Format: ${REPOSITORY_FORMAT}"
echo "  Location: ${REGION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Provide example Docker commands
print_info "Example Docker commands:"
echo ""
echo "# Build and tag your image:"
echo "docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/jplaw2epub-server:latest ."
echo ""
echo "# Push the image:"
echo "docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/jplaw2epub-server:latest"
echo ""
echo "# Pull the image:"
echo "docker pull ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/jplaw2epub-server:latest"
echo ""

# Check IAM permissions for service account (if using Workload Identity)
if [ -n "${SERVICE_ACCOUNT_EMAIL:-}" ]; then
    print_info "Granting Artifact Registry permissions to service account..."
    gcloud artifacts repositories add-iam-policy-binding "${REPOSITORY_NAME}" \
        --location="${REGION}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/artifactregistry.writer" \
        --project="${PROJECT_ID}"
    
    print_success "Permissions granted to ${SERVICE_ACCOUNT_EMAIL}"
fi

# Verify repository is accessible
print_info "Verifying repository access..."
if gcloud artifacts repositories list \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --format="table(name,format)" | grep -q "${REPOSITORY_NAME}"; then
    print_success "✅ Artifact Registry repository is ready for use!"
else
    print_error "Failed to verify repository access"
    exit 1
fi

# Save configuration for GitHub Actions
print_info "GitHub Actions configuration:"
echo ""
echo "Add the following to your GitHub repository secrets:"
echo "  ARTIFACT_REGISTRY_REPOSITORY: ${REPOSITORY_NAME}"
echo "  ARTIFACT_REGISTRY_REGION: ${REGION}"
echo ""
echo "Or use these values directly in your workflow:"
echo "  Repository: cloud-run-source-deploy"
echo "  Region: ${REGION}"