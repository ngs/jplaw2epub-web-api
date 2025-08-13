# Custom Domain Setup for Cloud Run

This guide explains how to set up a custom domain for your Cloud Run service.

## Prerequisites

- A deployed Cloud Run service
- A domain name that you own
- Access to your domain's DNS settings
- `gcloud` CLI installed and authenticated

## Setup Methods

### Method 1: Using the Setup Script (Recommended)

#### 1. Set Environment Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export DOMAIN="api.yourdomain.com"  # Your custom domain
export REGION="asia-northeast1"     # Your Cloud Run region
export SERVICE_NAME="jplaw2epub-api"  # Your Cloud Run service name
```

#### 2. Run the Domain Setup

```bash
# Run domain setup
./scripts/gcp-setup.sh domain
```

The script will:
1. Verify your Cloud Run service exists
2. Create a domain mapping
3. Display the DNS records you need to configure

#### 3. Configure DNS Records

Add the DNS records shown by the script to your domain provider:

**For subdomain (e.g., api.yourdomain.com):**
- Type: CNAME
- Name: api (or your subdomain)
- Value: ghs.googlehosted.com

**For root domain (e.g., yourdomain.com):**
- Type: A
- Name: @ (or leave blank)
- Values: 
  - 216.239.32.21
  - 216.239.34.21
  - 216.239.36.21
  - 216.239.38.21

#### 4. Verify Domain Setup

After configuring DNS (wait 10-30 minutes for propagation):

```bash
# Check status including domain
./scripts/gcp-setup.sh status
```

The verification script will check:
- DNS propagation status
- SSL certificate provisioning
- Domain connectivity

### Method 2: Manual Setup via Console

1. Go to [Cloud Run Console](https://console.cloud.google.com/run)
2. Select your service
3. Click "MANAGE CUSTOM DOMAINS"
4. Click "ADD MAPPING"
5. Enter your domain name
6. Follow the instructions to verify domain ownership
7. Configure the provided DNS records

### Method 3: Manual Setup via CLI

#### 1. Create Domain Mapping

```bash
gcloud run domain-mappings create \
    --service=jplaw2epub-api \
    --domain=api.yourdomain.com \
    --region=asia-northeast1
```

#### 2. Get DNS Configuration

```bash
gcloud run domain-mappings describe \
    --domain=api.yourdomain.com \
    --region=asia-northeast1
```

#### 3. Configure DNS Records

Based on the output, configure your DNS:

```bash
# View required DNS records
gcloud run domain-mappings describe \
    --domain=api.yourdomain.com \
    --region=asia-northeast1 \
    --format="value(status.resourceRecords[].type,status.resourceRecords[].rrdata)"
```

## Domain Verification Methods

### For Google Domains

If using Google Domains:
1. DNS records are automatically configured
2. No manual DNS configuration needed

### For External DNS Providers

Common providers and where to add DNS records:

**Cloudflare:**
1. Log in to Cloudflare Dashboard
2. Select your domain
3. Go to DNS settings
4. Add CNAME or A records
5. Set Proxy status to "DNS only" (gray cloud)

**Namecheap:**
1. Sign in to Namecheap
2. Go to Domain List
3. Click "Manage" next to your domain
4. Go to "Advanced DNS"
5. Add new records

**GoDaddy:**
1. Sign in to GoDaddy
2. Go to My Products
3. Click DNS next to your domain
4. Add records in the DNS Management page

## SSL Certificate

Google automatically provisions SSL certificates for custom domains:

- **Provisioning Time**: Up to 24 hours after DNS verification
- **Certificate Type**: Managed SSL certificate (Let's Encrypt)
- **Auto-renewal**: Certificates automatically renew
- **No additional cost**: SSL certificates are free

## Testing Your Domain

Once configured, test your domain:

```bash
# Test health endpoint
curl https://api.yourdomain.com/health

# Test GraphQL endpoint
curl -X POST https://api.yourdomain.com/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ laws(limit: 1) { totalCount } }"}'

# Check SSL certificate
openssl s_client -connect api.yourdomain.com:443 -servername api.yourdomain.com < /dev/null
```

## Multiple Domains

To add multiple domains to the same service:

```bash
# Add additional domain
gcloud run domain-mappings create \
    --service=jplaw2epub-api \
    --domain=www.yourdomain.com \
    --region=asia-northeast1

# List all domain mappings
gcloud run domain-mappings list --region=asia-northeast1
```

## Troubleshooting

### DNS Not Propagating

```bash
# Check DNS propagation
dig api.yourdomain.com

# Check from Google's DNS
dig @8.8.8.8 api.yourdomain.com

# Check CNAME record
dig CNAME api.yourdomain.com +short

# Check A records
dig A yourdomain.com +short
```

### SSL Certificate Not Active

If SSL certificate remains pending:

1. Verify DNS records are correctly configured
2. Check domain mapping status:
```bash
gcloud run domain-mappings describe \
    --domain=api.yourdomain.com \
    --region=asia-northeast1 \
    --format="get(status)"
```

3. Wait up to 24 hours for provisioning
4. Ensure CAA records don't block Let's Encrypt:
```bash
dig CAA yourdomain.com
```

### Domain Mapping Errors

Common errors and solutions:

**"Domain mapping already exists"**
- Delete existing mapping and recreate:
```bash
gcloud run domain-mappings delete \
    --domain=api.yourdomain.com \
    --region=asia-northeast1
```

**"Unauthorized to map domain"**
- Verify domain ownership through Search Console
- Ensure you have the correct IAM permissions

**"Service not found"**
- Verify service name and region:
```bash
gcloud run services list --region=asia-northeast1
```

## Removing Custom Domain

To remove a custom domain:

```bash
# Delete domain mapping
gcloud run domain-mappings delete \
    --domain=api.yourdomain.com \
    --region=asia-northeast1

# Remove DNS records from your DNS provider
```

## Best Practices

1. **Use subdomains for APIs**: Use `api.yourdomain.com` instead of root domain
2. **Set up monitoring**: Monitor domain health and SSL certificate expiry
3. **Configure CORS**: Update CORS settings for your custom domain
4. **Update environment variables**: Update your app configuration with the custom domain
5. **Set up redirects**: Redirect old Cloud Run URL to custom domain

## Integration with CI/CD

Add domain verification to your deployment workflow:

```yaml
# .github/workflows/deploy.yml
- name: Verify custom domain
  run: |
    DOMAIN_STATUS=$(gcloud run domain-mappings describe \
      --domain=${{ secrets.CUSTOM_DOMAIN }} \
      --region=${{ env.REGION }} \
      --format="value(status.certificates[].status)")
    
    if [ "$DOMAIN_STATUS" != "ACTIVE" ]; then
      echo "Warning: SSL certificate not active for custom domain"
    fi
```

## Security Considerations

1. **Always use HTTPS**: Cloud Run automatically redirects HTTP to HTTPS
2. **HSTS Headers**: Consider adding HSTS headers in your application
3. **CSP Headers**: Implement Content Security Policy headers
4. **Rate Limiting**: Implement rate limiting at application level

## Cost

Custom domains on Cloud Run are free:
- No additional charges for domain mapping
- Free managed SSL certificates
- You only pay for Cloud Run usage

## Support

For issues with custom domains:
1. Check Cloud Run [quotas and limits](https://cloud.google.com/run/quotas)
2. Review [domain mapping documentation](https://cloud.google.com/run/docs/mapping-custom-domains)
3. Contact Google Cloud Support for enterprise accounts