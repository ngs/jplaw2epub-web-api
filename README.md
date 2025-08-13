# jplaw2epub-web-api

Web API server for converting Japanese law documents to EPUB format.

This project provides REST and GraphQL APIs for:
- Converting Japanese Standard Law XML Schema to EPUB files
- Querying Japanese law data via GraphQL
- Fetching and converting laws by ID

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
./jplaw2epub-server
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
./jplaw2epub-server

# Specify port via flag
./jplaw2epub-server -port 8080

# Using environment variable
PORT=8080 ./jplaw2epub-server

# Using Make
make run
```

## API Endpoints

### REST API

- **POST /convert** - Convert XML to EPUB
  ```sh
  curl -X POST -H "Content-Type: application/xml" \
    --data-binary @law.xml \
    http://localhost:8080/convert -o output.epub
  ```

- **GET /epubs/{law_id}** - Get EPUB by law ID
  ```sh
  curl http://localhost:8080/epubs/325AC0000000131 -o radio_act.epub
  ```

- **GET /health** - Health check endpoint

### GraphQL API

- **POST/GET /graphql** - GraphQL endpoint
- **GET /graphiql** - Interactive GraphQL playground

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
./jplaw2epub-server

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
docker build -t jplaw2epub-server .
docker run -p 8080:8080 jplaw2epub-server
```

## Google Cloud Run Deployment

### Prerequisites

- Google Cloud SDK installed
- Project configured
- Cloud Run API enabled

### Manual Deployment

```bash
# 1. Build container image
gcloud builds submit \
  --tag gcr.io/YOUR_PROJECT_ID/jplaw2epub-server

# 2. Deploy to Cloud Run
gcloud run deploy jplaw2epub-server \
  --image gcr.io/YOUR_PROJECT_ID/jplaw2epub-server \
  --region asia-northeast1 \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --max-instances 10 \
  --min-instances 0 \
  --timeout 60
```

### Automated Deployment with Cloud Build

```bash
gcloud builds submit \
  --config cloudbuild.yaml \
  --substitutions=_REGION=asia-northeast1
```

### Continuous Deployment with GitHub

1. Create Cloud Build trigger
```bash
gcloud builds triggers create github \
  --repo-name=jplaw2epub-web-api \
  --repo-owner=YOUR_GITHUB_USERNAME \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml
```

2. Automatic deployment will run on push to main branch

## Environment Variables

- `PORT` - Server listening port (default: auto-select)

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
gcloud run services update jplaw2epub-server --memory 1Gi
```

### Timeout Error
For longer processing times, extend timeout:
```bash
gcloud run services update jplaw2epub-server --timeout 300
```

## Dependencies

- [jplaw2epub](https://github.com/ngs/jplaw2epub) - Core EPUB conversion library
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