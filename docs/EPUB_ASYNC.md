# EPUB Asynchronous Generation Feature

## Overview

To avoid timeouts during large EPUB file generation, we have implemented asynchronous processing using Cloud Run Jobs and Cloud Storage.

## Architecture

```
[Client] → [Cloud Run (GraphQL API)] → [Cloud Run Jobs API] → [Cloud Run Job]
                    ↓                                              ↓
              status check                                   EPUB generation
                    ↓                                              ↓
              [Cloud Storage] ←────────────────────────────────────┘
```

## Setup Instructions

### 1. Creating Cloud Storage Bucket

Cloud Storage setup is done in the [jplaw2epub-generate-epub-job](https://github.com/ngs/jplaw2epub-generate-epub-job) repository.

### 2. Deploying Cloud Run Job

Deploy the separate repository [jplaw2epub-generate-epub-job](https://github.com/ngs/jplaw2epub-generate-epub-job) as a Cloud Run Job.

```bash
# Run inside the repository
./deploy-job.sh
```

### 3. Updating Cloud Run Service

Either auto-deployed via GitHub Actions or manually run:

```bash
gcloud run services update jplaw2epub-api \
  --update-env-vars PROJECT_ID=YOUR_PROJECT_ID,EPUB_BUCKET_NAME=epub-storage,EPUB_JOB_NAME=epub-generator,REGION=asia-northeast1 \
  --region=asia-northeast1
```

## Usage

### GraphQL Query

```graphql
query GetEpub($id: String!) {
  epub(id: $id) {
    id
    status  # PENDING | PROCESSING | COMPLETED | FAILED
    signedUrl  # Download URL when generation is complete
    error  # Error message when failed
  }
}
```

### Client Implementation Example

```javascript
async function downloadEpub(id) {
  const pollInterval = 3000; // 3 seconds
  const maxAttempts = 100; // Maximum 5 minutes
  let attempts = 0;

  while (attempts < maxAttempts) {
    const { data } = await client.query({
      query: GET_EPUB_QUERY,
      variables: { id },
      fetchPolicy: 'network-only'
    });

    switch (data.epub.status) {
      case 'COMPLETED':
        window.location.href = data.epub.signedUrl;
        return;
      
      case 'FAILED':
        throw new Error(data.epub.error || 'EPUB generation failed');
      
      case 'PENDING':
      case 'PROCESSING':
        await new Promise(resolve => setTimeout(resolve, pollInterval));
        attempts++;
        break;
    }
  }
  
  throw new Error('Timeout occurred');
}
```

## File Structure

```
Cloud Storage (epub-storage/)
├── v1.0.0/                           # App version
│   ├── {id}.epub                    # Generated EPUB
│   └── {id}.status                  # Processing status
```

## Environment Variables

- `PROJECT_ID`: GCP project ID
- `EPUB_BUCKET_NAME`: Cloud Storage bucket name (default: epub-storage)
- `EPUB_JOB_NAME`: Cloud Run Job name (default: epub-generator)
- `REGION`: Region (default: asia-northeast1)

## Cost

For 1000 EPUB generations per month (assuming 1 minute per job):
- Cloud Run Jobs: ~$0.40 (CPU: $0.32 + Memory: $0.08)
- Cloud Storage: ~$0.07
- Total: ~$0.47/month

## Troubleshooting

### EPUB Not Being Generated

1. Check Cloud Run Job execution status:
```bash
gcloud run jobs executions list --job=epub-generator --region=asia-northeast1
```

2. Check logs for a specific execution:
```bash
gcloud run jobs executions logs EXECUTION_ID --job=epub-generator --region=asia-northeast1
```

2. Check Cloud Storage bucket permissions:
```bash
gsutil iam get gs://epub-storage
```

### Timeout Error

Check Cloud Run Job timeout setting (currently 1 hour):
```bash
gcloud run jobs describe epub-generator --region=asia-northeast1
```