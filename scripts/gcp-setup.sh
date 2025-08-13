#!/bin/bash

set -euo pipefail

# ============================================================================
# GCP Setup Tool for jplaw2epub Web API
# 
# This script handles all GCP setup and configuration for deploying
# the application to Cloud Run with GitHub Actions.
# 
# Usage:
#   ./scripts/gcp-setup.sh [command]
# 
# Commands:
#   all          - Run complete setup (default)
#   wif          - Setup Workload Identity Federation
#   permissions  - Fix all IAM permissions
#   registry     - Setup Artifact Registry
#   domain       - Setup custom domain
#   status       - Check current configuration status
#   help         - Show this help message
# ============================================================================

# Configuration (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-}"
GITHUB_ORG="${GITHUB_ORG:-ngs}"
GITHUB_REPO="${GITHUB_REPO:-jplaw2epub-web-api}"
REGION="${REGION:-asia-northeast1}"
SERVICE_NAME="${SERVICE_NAME:-jplaw2epub-api}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-github-actions-sa}"
POOL_NAME="${POOL_NAME:-github-pool}"
PROVIDER_NAME="${PROVIDER_NAME:-github-provider}"
REPOSITORY_NAME="${REPOSITORY_NAME:-cloud-run-source-deploy}"
DOMAIN="${DOMAIN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
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

# Validation function
validate_project() {
    if [ -z "${PROJECT_ID}" ]; then
        print_error "PROJECT_ID is not set"
        echo ""
        echo "Please set it using:"
        echo "  export PROJECT_ID=your-project-id"
        echo ""
        echo "Or create a .env file with:"
        echo "  PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed"
        echo "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        print_error "Project ${PROJECT_ID} does not exist or you don't have access"
        exit 1
    fi
}

# Get project number
get_project_number() {
    gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)"
}

# Enable required APIs
enable_apis() {
    print_step "Enabling Required APIs"
    
    local apis=(
        "iamcredentials.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "sts.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "artifactregistry.googleapis.com"
        "containerregistry.googleapis.com"
        "storage.googleapis.com"
        "serviceusage.googleapis.com"
        "logging.googleapis.com"
    )
    
    print_info "Enabling ${#apis[@]} APIs..."
    gcloud services enable "${apis[@]}" --project="${PROJECT_ID}"
    print_success "APIs enabled"
}

# Setup Workload Identity Federation
setup_wif() {
    print_step "Setting up Workload Identity Federation"
    
    # Create Workload Identity Pool
    print_info "Creating Workload Identity Pool..."
    if gcloud iam workload-identity-pools describe "${POOL_NAME}" \
        --location="global" \
        --project="${PROJECT_ID}" &>/dev/null; then
        print_warning "Pool '${POOL_NAME}' already exists"
    else
        gcloud iam workload-identity-pools create "${POOL_NAME}" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --display-name="GitHub Actions Pool" \
            --description="Workload Identity Pool for GitHub Actions"
        print_success "Pool created"
    fi
    
    # Create Workload Identity Provider
    print_info "Creating Workload Identity Provider..."
    if gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
        --workload-identity-pool="${POOL_NAME}" \
        --location="global" \
        --project="${PROJECT_ID}" &>/dev/null; then
        print_warning "Provider '${PROVIDER_NAME}' already exists"
    else
        gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool="${POOL_NAME}" \
            --display-name="GitHub Provider" \
            --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
            --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
            --issuer-uri="https://token.actions.githubusercontent.com"
        print_success "Provider created"
    fi
    
    # Create Service Account
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    print_info "Creating Service Account..."
    if gcloud iam service-accounts describe "${sa_email}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        print_warning "Service account '${sa_email}' already exists"
    else
        gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --project="${PROJECT_ID}" \
            --display-name="GitHub Actions Service Account" \
            --description="Service account for GitHub Actions CI/CD"
        print_success "Service account created"
    fi
    
    # Bind service account to Workload Identity Pool
    print_info "Binding service account to Workload Identity Pool..."
    local pool_id=$(gcloud iam workload-identity-pools describe "${POOL_NAME}" \
        --project="${PROJECT_ID}" \
        --location="global" \
        --format="value(name)")
    
    gcloud iam service-accounts add-iam-policy-binding "${sa_email}" \
        --project="${PROJECT_ID}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/${pool_id}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"
    
    print_success "Workload Identity Federation configured"
}

# Setup IAM permissions
setup_permissions() {
    print_step "Configuring IAM Permissions"
    
    local project_number=$(get_project_number)
    local github_sa="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    local cloudbuild_sa="${project_number}@cloudbuild.gserviceaccount.com"
    local compute_sa="${project_number}-compute@developer.gserviceaccount.com"
    
    # Roles for GitHub Actions service account
    print_info "Configuring GitHub Actions service account permissions..."
    local github_roles=(
        "roles/run.developer"
        "roles/storage.admin"
        "roles/artifactregistry.writer"
        "roles/iam.serviceAccountUser"
        "roles/cloudbuild.builds.editor"
        "roles/serviceusage.serviceUsageConsumer"
    )
    
    for role in "${github_roles[@]}"; do
        print_info "  Adding ${role}..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${github_sa}" \
            --role="${role}" \
            --condition=None &>/dev/null || print_warning "    Role might already exist"
    done
    
    # Roles for Cloud Build service account
    print_info "Configuring Cloud Build service account permissions..."
    local cloudbuild_roles=(
        "roles/run.admin"
        "roles/iam.serviceAccountUser"
        "roles/storage.admin"
        "roles/artifactregistry.writer"
        "roles/logging.logWriter"
    )
    
    for role in "${cloudbuild_roles[@]}"; do
        print_info "  Adding ${role}..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${cloudbuild_sa}" \
            --role="${role}" \
            --condition=None &>/dev/null || print_warning "    Role might already exist"
    done
    
    # Roles for Compute Engine service account
    print_info "Configuring Compute Engine service account permissions..."
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${compute_sa}" \
        --role="roles/cloudbuild.builds.builder" \
        --condition=None &>/dev/null || print_warning "  Role might already exist"
    
    print_success "IAM permissions configured"
}

# Setup Artifact Registry
setup_registry() {
    print_step "Setting up Artifact Registry"
    
    print_info "Creating Artifact Registry repository..."
    if gcloud artifacts repositories describe "${REPOSITORY_NAME}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        print_warning "Repository '${REPOSITORY_NAME}' already exists"
    else
        gcloud artifacts repositories create "${REPOSITORY_NAME}" \
            --repository-format="docker" \
            --location="${REGION}" \
            --description="Docker repository for Cloud Run deployments" \
            --project="${PROJECT_ID}"
        print_success "Repository created"
    fi
    
    # Configure Docker authentication
    print_info "Configuring Docker authentication..."
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    print_success "Artifact Registry configured"
    echo ""
    print_info "Repository URL:"
    echo "  ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
}

# Setup custom domain
setup_domain() {
    if [ -z "${DOMAIN}" ]; then
        print_error "DOMAIN is not set"
        echo "Please set it using: export DOMAIN=api.yourdomain.com"
        return 1
    fi
    
    print_step "Setting up Custom Domain: ${DOMAIN}"
    
    # Check if service exists
    if ! gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        print_error "Service '${SERVICE_NAME}' not found. Please deploy it first."
        return 1
    fi
    
    # Create domain mapping
    print_info "Creating domain mapping..."
    if gcloud run domain-mappings describe \
        --domain="${DOMAIN}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        print_warning "Domain mapping already exists"
    else
        gcloud run domain-mappings create \
            --service="${SERVICE_NAME}" \
            --domain="${DOMAIN}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}"
    fi
    
    # Get DNS records
    print_info "DNS Configuration Required:"
    echo ""
    gcloud run domain-mappings describe \
        --domain="${DOMAIN}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" \
        --format="table(status.resourceRecords[].type:label=TYPE,status.resourceRecords[].name:label=NAME,status.resourceRecords[].rrdata:label=VALUE)"
    
    echo ""
    print_info "Add these DNS records to your domain provider"
    print_success "Domain mapping created"
}

# Check status
check_status() {
    print_step "Configuration Status Check"
    
    local project_number=$(get_project_number)
    local github_sa="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    echo -e "${CYAN}Project Information:${NC}"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Project Number: ${project_number}"
    echo "  Region: ${REGION}"
    echo ""
    
    # Check APIs
    echo -e "${CYAN}API Status:${NC}"
    local required_apis=(
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        if gcloud services list --enabled --filter="name:${api}" \
            --project="${PROJECT_ID}" --format="value(name)" | grep -q "${api}"; then
            echo -e "  ${GREEN}✓${NC} ${api}"
        else
            echo -e "  ${RED}✗${NC} ${api}"
        fi
    done
    echo ""
    
    # Check Workload Identity
    echo -e "${CYAN}Workload Identity Federation:${NC}"
    if gcloud iam workload-identity-pools describe "${POOL_NAME}" \
        --location="global" \
        --project="${PROJECT_ID}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Pool: ${POOL_NAME}"
    else
        echo -e "  ${RED}✗${NC} Pool: ${POOL_NAME}"
    fi
    
    if gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
        --workload-identity-pool="${POOL_NAME}" \
        --location="global" \
        --project="${PROJECT_ID}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Provider: ${PROVIDER_NAME}"
    else
        echo -e "  ${RED}✗${NC} Provider: ${PROVIDER_NAME}"
    fi
    
    if gcloud iam service-accounts describe "${github_sa}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Service Account: ${github_sa}"
    else
        echo -e "  ${RED}✗${NC} Service Account: ${github_sa}"
    fi
    echo ""
    
    # Check Artifact Registry
    echo -e "${CYAN}Artifact Registry:${NC}"
    if gcloud artifacts repositories describe "${REPOSITORY_NAME}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Repository: ${REPOSITORY_NAME}"
        echo "     URL: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
    else
        echo -e "  ${RED}✗${NC} Repository: ${REPOSITORY_NAME}"
    fi
    echo ""
    
    # Check Cloud Run service
    echo -e "${CYAN}Cloud Run Service:${NC}"
    if gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        local service_url=$(gcloud run services describe "${SERVICE_NAME}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --format="value(status.url)")
        echo -e "  ${GREEN}✓${NC} Service: ${SERVICE_NAME}"
        echo "     URL: ${service_url}"
    else
        echo -e "  ${YELLOW}○${NC} Service: ${SERVICE_NAME} (not deployed yet)"
    fi
    echo ""
    
    # Show GitHub secrets needed
    local provider_id=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
        --project="${PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool="${POOL_NAME}" \
        --format="value(name)" 2>/dev/null || echo "NOT_CONFIGURED")
    
    if [ "${provider_id}" != "NOT_CONFIGURED" ]; then
        echo -e "${CYAN}GitHub Secrets Required:${NC}"
        echo ""
        echo "  PROJECT_ID:"
        echo "  ${PROJECT_ID}"
        echo ""
        echo "  WIF_PROVIDER:"
        echo "  ${provider_id}"
        echo ""
        echo "  WIF_SERVICE_ACCOUNT:"
        echo "  ${github_sa}"
        echo ""
        echo "  Add these at: https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/settings/secrets/actions"
    fi
}

# Show help
show_help() {
    cat << EOF
GCP Setup Tool for jplaw2epub Web API

Usage:
  $0 [command]

Commands:
  all          Run complete setup (default)
  wif          Setup Workload Identity Federation
  permissions  Fix all IAM permissions
  registry     Setup Artifact Registry
  domain       Setup custom domain
  status       Check current configuration status
  help         Show this help message

Environment Variables:
  PROJECT_ID    GCP Project ID (required)
  GITHUB_ORG    GitHub organization/username (default: ngs)
  GITHUB_REPO   GitHub repository name (default: jplaw2epub-web-api)
  REGION        GCP region (default: asia-northeast1)
  SERVICE_NAME  Cloud Run service name (default: jplaw2epub-api)
  DOMAIN        Custom domain (required for domain command)

Examples:
  # Run complete setup
  export PROJECT_ID=my-project
  $0 all

  # Check status
  $0 status

  # Setup custom domain
  export DOMAIN=api.example.com
  $0 domain

EOF
}

# Complete setup
run_all() {
    print_step "Complete GCP Setup"
    
    enable_apis
    setup_wif
    setup_permissions
    setup_registry
    
    echo ""
    print_success "Complete setup finished!"
    echo ""
    check_status
}

# Main execution
main() {
    local command="${1:-all}"
    
    # Load .env file if exists
    if [ -f .env ]; then
        export $(grep -v '^#' .env | xargs)
    fi
    
    case "${command}" in
        all)
            validate_project
            run_all
            ;;
        wif)
            validate_project
            enable_apis
            setup_wif
            ;;
        permissions)
            validate_project
            setup_permissions
            ;;
        registry)
            validate_project
            setup_registry
            ;;
        domain)
            validate_project
            setup_domain
            ;;
        status)
            validate_project
            check_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: ${command}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"