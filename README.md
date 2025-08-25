# jplaw2epub-web-api

Web API server for converting Japanese law documents to EPUB format.

This project provides GraphQL APIs for:
- Asynchronous EPUB generation using Cloud Run Jobs (handles large files without timeouts)
- Querying Japanese law data via GraphQL
- Converting Japanese Standard Law XML Schema to EPUB files with status tracking
- Searching laws by category, type, title, and keywords

## Quick Start

```bash
# Clone repository
git clone https://github.com/ngs/jplaw2epub-web-api.git
cd jplaw2epub-web-api

# Install dependencies
make deps

# Run linter and format code
make fmt lint

# Build and run
make build
./jplaw2epub-api
```

## Installation

### Install from Go module

```sh
go install go.ngs.io/jplaw2epub-web-api@latest
```

### Build from source

```sh
git clone https://github.com/ngs/jplaw2epub-web-api.git
cd jplaw2epub-web-api
make build
```

## Running the Server

```sh
# Use automatic port selection
./jplaw2epub-api

# Specify port via flag
./jplaw2epub-api -port 8080

# Enable CORS for specific origins
./jplaw2epub-api -cors-origins "https://example.com,https://app.example.com"

# Allow all origins (use with caution)
./jplaw2epub-api -cors-origins "*"

# Using environment variables
PORT=8080 CORS_ORIGINS="https://example.com" ./jplaw2epub-api

# Using Make
make run
```

### Command-line Flags

- `-port` - Server listening port (default: auto-select, falls back to PORT env var)
- `-cors-origins` - Comma-separated list of allowed CORS origins (default: none, falls back to CORS_ORIGINS env var)

## CORS Configuration

The server supports Cross-Origin Resource Sharing (CORS) configuration to allow web applications from specific domains to access the API.

### Examples

```sh
# Allow requests from multiple domains
./jplaw2epub-api -cors-origins "https://mydomain.com,https://app.mydomain.com"

# Allow all origins (development only - use with caution)
./jplaw2epub-api -cors-origins "*"

# Via environment variable
export CORS_ORIGINS="https://mydomain.com,https://app.mydomain.com"
./jplaw2epub-api
```

### Deployment with CORS

For production deployments, configure CORS origins using:

1. **GitHub Secrets**: Add `CORS_ORIGINS` secret with comma-separated URLs
2. **Environment Variables**: Set `CORS_ORIGINS` in your deployment environment
3. **Command-line Flag**: Use `-cors-origins` flag when running the server

## API Endpoints

### REST API

- **GET /health** - Health check endpoint

### GraphQL API

- **POST/GET /graphql** - GraphQL endpoint
- **GET /graphiql** - Interactive GraphQL playground

#### EPUB Generation (Asynchronous)

The API now uses asynchronous EPUB generation with Cloud Run Jobs to handle large files without timeouts:

```graphql
query GetEpub($id: String!) {
  epub(id: $id) {
    id
    status      # PENDING | PROCESSING | COMPLETED | FAILED
    signedUrl   # Download URL when completed
    error       # Error message if failed
  }
}
```

Example client implementation:
```javascript
async function downloadEpub(id) {
  const pollInterval = 3000; // 3 seconds
  const maxAttempts = 100;   // Max 5 minutes
  
  for (let i = 0; i < maxAttempts; i++) {
    const { data } = await client.query({
      query: GET_EPUB_QUERY,
      variables: { id },
      fetchPolicy: 'network-only'
    });
    
    if (data.epub.status === 'COMPLETED') {
      window.location.href = data.epub.signedUrl;
      return;
    }
    
    if (data.epub.status === 'FAILED') {
      throw new Error(data.epub.error || 'EPUB generation failed');
    }
    
    await new Promise(resolve => setTimeout(resolve, pollInterval));
  }
  
  throw new Error('Timeout');
}
```

#### Example Queries

Search laws by category and type:
```graphql
query {
  laws(
    categoryCode: [CONSTITUTION, CRIMINAL]
    lawType: [ACT]
    limit: 5
  ) {
    totalCount
    laws {
      lawInfo {
        lawId
        lawNum
        lawType
        promulgationDate
      }
      revisionInfo {
        lawTitle
        lawTitleKana
      }
    }
  }
}
```

Get law revisions:
```graphql
query {
  revisions(lawId: "325AC0000000131") {
    lawInfo {
      lawNum
      promulgationDate
    }
    revisions {
      amendmentLawTitle
      amendmentEnforcementDate
      currentRevisionStatus
    }
  }
}
```

Keyword search:
```graphql
query {
  keyword(keyword: "無線", limit: 3) {
    totalCount
    items {
      lawInfo {
        lawId
      }
      revisionInfo {
        lawTitle
      }
      sentences {
        text
        position
      }
    }
  }
}
```

Search laws by title:
```bash
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ laws(lawTitle: \"電波\", limit: 5) { totalCount laws { lawInfo { lawId lawNum } revisionInfo { lawTitle } } } }"}'
```

## Asynchronous EPUB Generation

### Architecture

The API uses Cloud Run Jobs and Cloud Storage for asynchronous EPUB generation to handle large files without timeouts:

```
[Client] → [Cloud Run API] → [Cloud Run Jobs API] → [Cloud Run Job]
               ↓                                          ↓
         status check                              EPUB generation
               ↓                                          ↓
         [Cloud Storage] ←────────────────────────────────┘
```

### Setup

1. **Deploy the EPUB Generation Job**: Deploy the [jplaw2epub-generate-epub-job](https://github.com/ngs/jplaw2epub-generate-epub-job) repository as a Cloud Run Job

2. **Configure Environment Variables**: Set the required environment variables when deploying the API:
   ```bash
   gcloud run services update jplaw2epub-api \
     --update-env-vars PROJECT_ID=YOUR_PROJECT_ID,\
   EPUB_BUCKET_NAME=epub-storage,\
   EPUB_JOB_NAME=epub-generator,\
   REGION=asia-northeast1 \
     --region=asia-northeast1
   ```

3. **Cloud Storage**: The job automatically creates and manages the storage bucket for EPUB files

### File Structure

```
Cloud Storage (epub-storage/)
├── v1.0.0/                    # App version
│   ├── {id}.epub             # Generated EPUB
│   └── {id}.status           # Processing status
```

## Development

### Prerequisites

- Go 1.23 or later
- golangci-lint (for linting)
- Docker (optional, for containerized deployment)

### Makefile Commands

```bash
make help          # Show help message
make run           # Run the server locally
make build         # Build the binary
make test          # Run tests
make lint          # Run linter
make fmt           # Format code
make clean         # Clean build artifacts
make deps          # Download and tidy dependencies
make docker-build  # Build Docker image
make docker-run    # Run Docker container
make gqlgen        # Generate GraphQL code
make install-tools # Install development tools
make all           # Run all checks and build
```

### Project Structure

```
.
├── main.go                 # Server entry point
├── Dockerfile              # Docker configuration
├── cloudbuild.yaml         # Google Cloud Build configuration
├── .golangci.yml           # Linter configuration
├── Makefile                # Build and development tasks
├── go.mod                  # Go module definition
├── go.sum                  # Go module checksums
├── graphql/                # GraphQL implementation
│   ├── schema.graphqls     # GraphQL schema definition
│   ├── resolver.go         # GraphQL resolvers
│   ├── schema.resolvers.go # Generated resolver implementations
│   ├── converters.go       # Type converters
│   ├── generated.go        # Generated code
│   ├── gqlgen.yml          # GraphQL code generation config
│   └── model/
│       └── models_gen.go   # Generated models
└── README.md               # This file
```

### Code Quality

This project uses `golangci-lint` with a comprehensive set of linters to ensure code quality:

- **gofmt** - Code formatting
- **goimports** - Import formatting and organization
- **govet** - Go vet checks
- **errcheck** - Error handling verification
- **staticcheck** - Static analysis
- **gosec** - Security checks
- **gocritic** - Opinionated linting
- **revive** - Comprehensive linting
- And many more...

Run linter:
```bash
make lint
```

Format code:
```bash
make fmt
```

### GraphQL Schema Development

The GraphQL schema is defined in `graphql/schema.graphqls`. To regenerate code after schema changes:

```sh
make gqlgen
# or manually
cd graphql
go run github.com/99designs/gqlgen generate
```

### Local Development

```bash
# Install development tools
make install-tools

# Download dependencies
make deps

# Format and lint code
make fmt lint

# Run tests
make test

# Build and run
make build
./jplaw2epub-api

# Or run directly
make run
```

## Docker Deployment

Build and run with Docker:

```sh
# Using Make
make docker-build
make docker-run

# Or manually
docker build -t jplaw2epub-api .
docker run -p 8080:8080 jplaw2epub-api
```

### Docker with CORS Configuration

```sh
# Build the image
docker build -t jplaw2epub-api .

# Method 1: Using environment variables
docker run -p 8080:8080 \
  -e CORS_ORIGINS="https://example.com,https://app.example.com" \
  jplaw2epub-api

# Method 2: Using command-line arguments
docker run -p 8080:8080 \
  jplaw2epub-api \
  -cors-origins "https://example.com,https://app.example.com"

# Method 3: Using argument syntax
docker run -p 8080:8080 \
  jplaw2epub-api \
  -cors-origins="https://example.com,https://app.example.com"

# Allow all origins (development only)
docker run -p 8080:8080 \
  jplaw2epub-api \
  -cors-origins "*"

# Specify both port and CORS origins
docker run -p 9000:9000 \
  jplaw2epub-api \
  -port 9000 \
  -cors-origins "https://example.com"

# Using docker-compose (see docker-compose.yml example below)
docker-compose up
```

## Google Cloud Run Deployment

### 🚀 Quick Setup

See [docs/SETUP.md](docs/SETUP.md) for complete setup guide.

```bash
# 1. Set environment variables
export PROJECT_ID="your-gcp-project-id"
export GITHUB_ORG="your-github-username"
export GITHUB_REPO="jplaw2epub-web-api"

# 2. Run setup
chmod +x scripts/gcp-setup.sh
./scripts/gcp-setup.sh all

# 3. Configure GitHub secrets
# Add WIF_PROVIDER, WIF_SERVICE_ACCOUNT, PROJECT_ID
# (Values are displayed by the setup script)
```

### Deployment Methods

#### Method 1: GitHub Actions (Recommended)

Automatic deployment on push to main/master:
```bash
git push origin main
```

Manual deployment available via GitHub Actions UI.

#### Method 2: Deploy from Source (Simplest)

```bash
gcloud run deploy jplaw2epub-api \
  --source . \
  --region=asia-northeast1 \
  --allow-unauthenticated \
  --port=8080
```

#### Method 3: Via Cloud Build

```bash
gcloud builds submit \
  --config=cloudbuild.yaml \
  --region=asia-northeast1
```

### Custom Domain Setup (Optional)

```bash
export DOMAIN="api.yourdomain.com"
./scripts/gcp-setup.sh domain
```

See [docs/CUSTOM_DOMAIN_SETUP.md](docs/CUSTOM_DOMAIN_SETUP.md) for details.

## Environment Variables

- `PORT` - Server listening port (default: auto-select)
- `CORS_ORIGINS` - Comma-separated list of allowed CORS origins (optional)
- `PROJECT_ID` - GCP Project ID (required for async EPUB generation)
- `EPUB_BUCKET_NAME` - Cloud Storage bucket name for EPUB files (default: epub-storage)
- `EPUB_JOB_NAME` - Cloud Run Job name for EPUB generation (default: epub-generator)
- `REGION` - GCP region (default: asia-northeast1)

## Recommended Cloud Run Settings

- **Region**: asia-northeast1 (Tokyo)
- **Memory**: 512Mi
- **Max instances**: 10
- **Min instances**: 0 (allows cold start)
- **Timeout**: 60 seconds
- **Concurrency**: 1000 (default)

## Troubleshooting

### Out of Memory Error
For large XML files, increase Cloud Run memory:
```bash
gcloud run services update jplaw2epub-api --memory 1Gi
```

### Timeout Error
For longer processing times, extend timeout:
```bash
gcloud run services update jplaw2epub-api --timeout 300
```

## Dependencies

- [jplaw-api-v2](https://go.ngs.io/jplaw-api-v2) - Japanese law API client
- [gqlgen](https://gqlgen.com/) - GraphQL code generation
- [golangci-lint](https://golangci-lint.run/) - Go linters aggregator

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests and linter (`make all`)
4. Commit your changes (`git commit -m 'Add some amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

MIT License

Copyright © 2025 Atsushi Nagase