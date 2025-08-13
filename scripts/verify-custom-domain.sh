#!/bin/bash

set -euo pipefail

# Load configuration if exists
if [ -f /tmp/domain-mapping-config.txt ]; then
    source /tmp/domain-mapping-config.txt
fi

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-asia-northeast1}"
SERVICE_NAME="${SERVICE_NAME:-jplaw2epub-api}"
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

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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

print_info "Verifying custom domain configuration"
print_info "Domain: ${DOMAIN}"
echo ""

# Set the project
gcloud config set project "${PROJECT_ID}"

# Check domain mapping status
print_info "Checking domain mapping status..."
MAPPING_STATUS=$(gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="value(status.mappedRouteName)" 2>/dev/null || echo "NOT_FOUND")

if [ "${MAPPING_STATUS}" == "NOT_FOUND" ]; then
    print_error "Domain mapping not found. Please run setup-custom-domain.sh first."
    exit 1
fi

# Check DNS propagation
print_info "Checking DNS propagation..."
echo ""

# Get expected DNS records
EXPECTED_RECORDS=$(gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="value(status.resourceRecords[].rrdata)")

RECORD_TYPE=$(gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="value(status.resourceRecords[].type)")

# Check actual DNS records
print_info "Expected ${RECORD_TYPE} records:"
for record in ${EXPECTED_RECORDS}; do
    echo "  - ${record}"
done
echo ""

print_info "Actual DNS records:"
if [ "${RECORD_TYPE}" == "CNAME" ]; then
    ACTUAL_RECORDS=$(dig +short CNAME "${DOMAIN}" 2>/dev/null || echo "DNS_LOOKUP_FAILED")
else
    ACTUAL_RECORDS=$(dig +short A "${DOMAIN}" 2>/dev/null || echo "DNS_LOOKUP_FAILED")
fi

if [ "${ACTUAL_RECORDS}" == "DNS_LOOKUP_FAILED" ] || [ -z "${ACTUAL_RECORDS}" ]; then
    print_warning "DNS records not found or not propagated yet"
    echo ""
    print_info "Please ensure you've added the DNS records to your domain provider"
    print_info "DNS propagation can take up to 48 hours"
    exit 1
else
    for record in ${ACTUAL_RECORDS}; do
        echo "  - ${record}"
    done
fi
echo ""

# Check SSL certificate status
print_info "Checking SSL certificate status..."
CERT_STATUS=$(gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="value(status.certificates[].status)" 2>/dev/null || echo "PENDING")

if [ "${CERT_STATUS}" == "ACTIVE" ]; then
    print_success "SSL certificate is active!"
else
    print_warning "SSL certificate status: ${CERT_STATUS}"
    print_info "Google will automatically provision an SSL certificate once DNS is verified"
    print_info "This process can take up to 24 hours after DNS propagation"
fi
echo ""

# Test the domain
print_info "Testing domain connectivity..."
echo ""

# Test HTTP redirect to HTTPS
print_info "Testing HTTP (should redirect to HTTPS):"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L "http://${DOMAIN}/health" 2>/dev/null || echo "000")
if [ "${HTTP_STATUS}" == "200" ]; then
    print_success "HTTP redirect working!"
else
    print_warning "HTTP status: ${HTTP_STATUS}"
fi

# Test HTTPS
print_info "Testing HTTPS:"
HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/health" 2>/dev/null || echo "000")
if [ "${HTTPS_STATUS}" == "200" ]; then
    print_success "HTTPS is working!"
    echo ""
    print_success "✅ Custom domain is fully configured and working!"
    echo ""
    print_info "Your service is available at:"
    echo "  https://${DOMAIN}"
elif [ "${HTTPS_STATUS}" == "000" ]; then
    print_warning "Cannot connect via HTTPS yet"
    print_info "This is normal if the SSL certificate is still being provisioned"
else
    print_warning "HTTPS status: ${HTTPS_STATUS}"
fi

echo ""
print_info "Domain mapping details:"
gcloud run domain-mappings describe \
    --domain="${DOMAIN}" \
    --region="${REGION}" \
    --format="table(
        metadata.name:label=DOMAIN,
        status.mappedRouteName:label=SERVICE,
        status.certificates[].status:label=SSL_STATUS,
        metadata.creationTimestamp:label=CREATED
    )"