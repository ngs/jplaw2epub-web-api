#!/bin/bash

set -euo pipefail

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-asia-northeast1}"
SERVICE_NAME="${SERVICE_NAME:-jplaw2epub-server}"
DOMAIN="${DOMAIN:-}"

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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check required parameters
if [ -z "${PROJECT_ID}" ]; then
    print_error "PROJECT_ID is not set. Please set it using: export PROJECT_ID=your-project-id"
    exit 1
fi

if [ -z "${DOMAIN}" ]; then
    print_error "DOMAIN is not set. Please set it using: export DOMAIN=your-domain.com"
    exit 1
fi

print_info "Setting up custom domain for Cloud Run service"
print_info "Project ID: ${PROJECT_ID}"
print_info "Region: ${REGION}"
print_info "Service: ${SERVICE_NAME}"
print_info "Domain: ${DOMAIN}"
echo ""

# Set the project
gcloud config set project "${PROJECT_ID}"

# Check if service exists
print_step "Checking if Cloud Run service exists..."
if ! gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
    print_error "Cloud Run service '${SERVICE_NAME}' not found in region '${REGION}'"
    print_info "Please deploy your service first using: gcloud run deploy ${SERVICE_NAME}"
    exit 1
fi

# Create domain mapping
print_step "Creating domain mapping..."
gcloud run domain-mappings create \
    --service="${SERVICE_NAME}" \
    --domain="${DOMAIN}" \
    --region="${REGION}" || print_warning "Domain mapping might already exist"

# Get DNS records to configure
print_step "Retrieving DNS configuration..."
echo ""
print_info "Please configure the following DNS records for your domain:"
echo ""

# Get the DNS records
DNS_RECORDS=$(gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="value(status.resourceRecords[].rrdata)")

RECORD_TYPE=$(gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="value(status.resourceRecords[].type)")

if [ "${RECORD_TYPE}" == "CNAME" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DNS Configuration Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Type: CNAME"
    echo "  Name: ${DOMAIN}"
    echo "  Value: ${DNS_RECORDS}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DNS Configuration Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Type: A"
    echo "  Name: ${DOMAIN}"
    echo "  Values:"
    for record in ${DNS_RECORDS}; do
        echo "    - ${record}"
    done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
print_info "Next steps:"
echo "  1. Add the above DNS records to your domain's DNS provider"
echo "  2. Wait for DNS propagation (usually 10-30 minutes, can take up to 48 hours)"
echo "  3. Run the verification script: ./scripts/verify-custom-domain.sh"
echo ""

# Save configuration for verification script
cat > /tmp/domain-mapping-config.txt << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
SERVICE_NAME=${SERVICE_NAME}
DOMAIN=${DOMAIN}
EOF

print_info "Configuration saved to /tmp/domain-mapping-config.txt"