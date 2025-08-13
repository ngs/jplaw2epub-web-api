# Deployment Options for Cloud Run

This document explains different deployment methods to fix the "Repository not found" error and deploy to Cloud Run.

## Quick Fix: Setup Artifact Registry

If you're getting the error `Repository "cloud-run-source-deploy" not found`, run:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Run the setup script
chmod +x scripts/setup-artifact-registry.sh
./scripts/setup-artifact-registry.sh
```

This will create the required Artifact Registry repository.

## Deployment Methods

### Option 1: Deploy from Source (Recommended for Simplicity)

**File:** `.github/workflows/deploy-source.yml`

This is the simplest method. Cloud Run builds your container automatically.

**Pros:**
- No need to manage Docker registries
- Simplest configuration
- Cloud Build handles everything automatically

**Cons:**
- Less control over build process
- Slightly slower (builds on every deploy)

**Usage:**
```bash
gcloud run deploy jplaw2epub-server \
  --source . \
  --region=asia-northeast1
```

### Option 2: Deploy via Cloud Build

**File:** `.github/workflows/deploy-cloudbuild.yml`

Uses Cloud Build to build and deploy your application.

**Pros:**
- More control over build process
- Can use build triggers
- Good for complex builds

**Cons:**
- Requires Cloud Build configuration
- More complex setup

**Usage:**
```bash
gcloud builds submit --config=cloudbuild.yaml
```

### Option 3: Deploy with Artifact Registry

**File:** `.github/workflows/deploy.yml`

Builds Docker image in GitHub Actions and pushes to Artifact Registry.

**Pros:**
- Full control over build process
- Can run tests before pushing
- Faster deployments (pre-built images)

**Cons:**
- Requires Artifact Registry setup
- More complex configuration

**Setup Required:**
1. Create Artifact Registry repository:
```bash
./scripts/setup-artifact-registry.sh
```

2. Configure Docker authentication:
```bash
gcloud auth configure-docker asia-northeast1-docker.pkg.dev
```

### Option 4: Use Google Container Registry (Legacy)

**Note:** GCR is being replaced by Artifact Registry but still works.

Update your workflow to use `gcr.io` instead:
```yaml
IMAGE_TAG="gcr.io/${PROJECT_ID}/${SERVICE_NAME}:${GITHUB_SHA}"
```

Enable Container Registry API:
```bash
gcloud services enable containerregistry.googleapis.com
```

## Choosing the Right Method

| Use Case | Recommended Method | Why |
|----------|-------------------|-----|
| Quick prototype | Deploy from Source | Simplest, no setup needed |
| Production with CI/CD | Artifact Registry | Best control and caching |
| Complex build requirements | Cloud Build | Powerful build options |
| Legacy systems | Container Registry | Already configured |

## Common Issues and Solutions

### Issue 1: Repository Not Found

**Error:** `name unknown: Repository "cloud-run-source-deploy" not found`

**Solutions:**

1. **Create the repository:**
```bash
gcloud artifacts repositories create cloud-run-source-deploy \
  --repository-format=docker \
  --location=asia-northeast1
```

2. **Or switch to deploy from source:**
Use `deploy-source.yml` workflow instead

3. **Or use Container Registry:**
Change image URLs from:
```
asia-northeast1-docker.pkg.dev/PROJECT_ID/cloud-run-source-deploy/...
```
To:
```
gcr.io/PROJECT_ID/...
```

### Issue 2: Authentication Failed

**Error:** `denied: Permission "artifactregistry.repositories.uploadArtifacts" denied`

**Solution:**
```bash
# Grant permissions to service account
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/artifactregistry.writer"
```

### Issue 3: Docker Not Configured

**Error:** `docker push` fails with authentication error

**Solution:**
```bash
# Configure Docker for Artifact Registry
gcloud auth configure-docker asia-northeast1-docker.pkg.dev

# Or for Container Registry
gcloud auth configure-docker
```

## Migration Path

If you want to migrate from one method to another:

### From Container Registry to Artifact Registry:

1. Create Artifact Registry repository:
```bash
./scripts/setup-artifact-registry.sh
```

2. Update image URLs in workflows:
```yaml
# Old (GCR)
IMAGE_TAG="gcr.io/${PROJECT_ID}/jplaw2epub-server:latest"

# New (Artifact Registry)
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/cloud-run-source-deploy/jplaw2epub-server:latest"
```

3. Update cloudbuild.yaml to use `cloudbuild-ar.yaml`

### From Manual Deploy to GitHub Actions:

1. Setup Workload Identity Federation:
```bash
./scripts/setup-workload-identity.sh
```

2. Add secrets to GitHub:
- `PROJECT_ID`
- `WIF_PROVIDER`
- `WIF_SERVICE_ACCOUNT`

3. Choose and enable a workflow:
- `deploy-source.yml` (simplest)
- `deploy.yml` (with Artifact Registry)
- `deploy-cloudbuild.yml` (with Cloud Build)

## Testing Deployments Locally

Before deploying, test locally:

```bash
# Build Docker image
docker build -t jplaw2epub-server:test .

# Run locally
docker run -p 8080:8080 -e PORT=8080 jplaw2epub-server:test

# Test
curl http://localhost:8080/health
```

## Monitoring Deployments

Check deployment status:
```bash
# View Cloud Run services
gcloud run services list --region=asia-northeast1

# View deployment logs
gcloud run services logs jplaw2epub-server --region=asia-northeast1

# View Cloud Build history
gcloud builds list --limit=5
```

## Rollback Strategy

If deployment fails:

```bash
# List revisions
gcloud run revisions list --service=jplaw2epub-server --region=asia-northeast1

# Rollback to previous revision
gcloud run services update-traffic jplaw2epub-server \
  --to-revisions=jplaw2epub-server-00001-abc=100 \
  --region=asia-northeast1
```

## Cost Optimization

- Use `--min-instances=0` for development
- Set appropriate `--max-instances` limits
- Use `--cpu-throttling` for non-latency-sensitive services
- Consider `--execution-environment=gen2` for better performance

## Security Considerations

1. **Never commit secrets** to repository
2. **Use Workload Identity Federation** instead of service account keys
3. **Enable vulnerability scanning** in Artifact Registry
4. **Use least privilege** IAM roles
5. **Enable Binary Authorization** for production

## Support

For help:
1. Check Cloud Run logs: `gcloud run services logs`
2. Review Cloud Build logs: `gcloud builds log [BUILD_ID]`
3. Check IAM permissions: `gcloud projects get-iam-policy`
4. Review [Cloud Run documentation](https://cloud.google.com/run/docs)