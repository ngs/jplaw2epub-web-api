# Workload Identity Federation Setup for GitHub Actions

This guide explains how to set up Workload Identity Federation (WIF) to authenticate GitHub Actions with Google Cloud Platform without using service account keys.

## Prerequisites

- Google Cloud Project with billing enabled
- `gcloud` CLI installed and authenticated
- GitHub repository with Actions enabled
- Required GCP APIs will be enabled by the setup script

## Setup Instructions

### 1. Set Environment Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export GITHUB_ORG="your-github-username-or-org"  # Default: ngs
export GITHUB_REPO="your-repo-name"              # Default: jplaw2epub-web-api
```

### 2. Run the Setup Script

```bash
# Make the script executable
chmod +x scripts/setup-workload-identity.sh

# Run the setup
./scripts/setup-workload-identity.sh
```

The script will:
- Enable required GCP APIs
- Create a Workload Identity Pool
- Create a Workload Identity Provider for GitHub
- Create a service account with necessary permissions
- Configure the binding between GitHub and the service account

### 3. Configure GitHub Secrets

After running the setup script, add the following secrets to your GitHub repository:

1. Go to your GitHub repository → Settings → Secrets and variables → Actions
2. Add the following repository secrets:
   - `WIF_PROVIDER`: The Workload Identity Provider resource name (output by the script)
   - `WIF_SERVICE_ACCOUNT`: The service account email (output by the script)
   - `PROJECT_ID`: Your GCP project ID

### 4. GitHub Actions Workflow

The repository includes two workflows that use Workload Identity Federation:

- `.github/workflows/deploy.yml`: Deploys to Cloud Run on push to main/master
- `.github/workflows/ci.yml`: Runs tests and builds

Both workflows use the following authentication step:

```yaml
permissions:
  contents: read
  id-token: write  # Required for WIF

steps:
  - id: 'auth'
    name: 'Authenticate to Google Cloud'
    uses: 'google-github-actions/auth@v2'
    with:
      workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
      service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}
```

## Manual Setup (Alternative)

If you prefer to set up manually or need to customize the configuration:

### 1. Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "github-pool" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

### 2. Create Workload Identity Provider

```bash
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

### 3. Create Service Account

```bash
gcloud iam service-accounts create "github-actions-sa" \
  --project="${PROJECT_ID}" \
  --display-name="GitHub Actions Service Account"
```

### 4. Grant Permissions

```bash
SERVICE_ACCOUNT_EMAIL="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant necessary roles
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/run.developer"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/artifactregistry.writer"
```

### 5. Bind Service Account to Workload Identity

```bash
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe "github-pool" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"
```

## Security Benefits

Using Workload Identity Federation provides several security advantages:

1. **No long-lived credentials**: No service account keys to manage or rotate
2. **Automatic credential management**: Tokens are short-lived and automatically refreshed
3. **Repository-scoped access**: Only the specified repository can authenticate
4. **Audit trail**: All actions are logged with the repository identity
5. **No secrets in code**: No risk of accidentally committing credentials

## Troubleshooting

### Permission Denied Errors

If you encounter permission errors:

1. Verify the service account has the necessary roles
2. Check that the repository attribute condition matches your repo
3. Ensure the `id-token: write` permission is set in the workflow

### Authentication Failures

1. Verify the WIF_PROVIDER and WIF_SERVICE_ACCOUNT secrets are correctly set
2. Check that the Workload Identity Pool and Provider exist
3. Ensure the GitHub Actions token is being properly generated

### Viewing Logs

```bash
# View Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50

# View service account activity
gcloud logging read "protoPayload.authenticationInfo.principalEmail=\"github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com\"" --limit=50
```

## Cleanup

To remove the Workload Identity Federation setup:

```bash
# Delete the service account binding
gcloud iam service-accounts remove-iam-policy-binding \
  "github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

# Delete the provider
gcloud iam workload-identity-pools providers delete "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-pool"

# Delete the pool
gcloud iam workload-identity-pools delete "github-pool" \
  --project="${PROJECT_ID}" \
  --location="global"

# Delete the service account
gcloud iam service-accounts delete "github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}"
```