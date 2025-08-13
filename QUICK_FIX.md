# Quick Fix Guide

## Deployment Failed?

### 1. Check GitHub Secrets

Make sure these are set in your repository settings:
- `PROJECT_ID` - Your GCP project ID
- `WIF_PROVIDER` - Workload Identity Provider (from setup script)
- `WIF_SERVICE_ACCOUNT` - Service account email (from setup script)

### 2. Run Local Fix

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Run the fix
./scripts/gcp-setup.sh all

# Wait for permissions to propagate
sleep 180
```

### 3. Try Simple Deployment

If the main workflow fails, try the simple deployment:
1. Go to Actions tab in GitHub
2. Select "Simple Deploy (First Time Setup)"
3. Click "Run workflow"

### 4. Common Issues

#### "Permission denied" errors
```bash
./scripts/gcp-setup.sh permissions
```

#### "Repository not found" error
```bash
./scripts/gcp-setup.sh registry
```

#### "API not enabled" error
```bash
gcloud services enable cloudbuild.googleapis.com run.googleapis.com \
  artifactregistry.googleapis.com storage.googleapis.com \
  --project=${PROJECT_ID}
```

#### "Reserved env name PORT" error
This happens when trying to set PORT environment variable.
Solution: Remove `--set-env-vars="PORT=8080"` from deployment commands.
Cloud Run automatically sets the PORT variable.

### 5. Check Status

```bash
# Check what's configured
./scripts/gcp-setup.sh status
```

### 6. Manual Deploy (Last Resort)

```bash
# Deploy directly from command line
gcloud run deploy jplaw2epub-api \
  --source . \
  --region=asia-northeast1 \
  --project=${PROJECT_ID} \
  --allow-unauthenticated
```

## Still Having Issues?

1. Check the error message in GitHub Actions logs
2. Make sure PROJECT_ID is correct
3. Ensure you have owner/editor permissions on the GCP project
4. Try running commands locally first to debug

## Need More Help?

See [docs/SETUP.md](docs/SETUP.md) for complete documentation.