# jplaw2epub-web-api

Web API server for converting Japanese law documents to EPUB format.

This project provides REST and GraphQL APIs for:
- Converting Japanese Standard Law XML Schema to EPUB files
- Querying Japanese law data via GraphQL
- Fetching and converting laws by ID

## Installation

```sh
go install go.ngs.io/jplaw2epub-web-api@latest
```

Or build from source:

```sh
git clone https://github.com/ngs/jplaw2epub-web-api.git
cd jplaw2epub-web-api
go build -o jplaw2epub-server .
```

## Running the Server

```sh
# Use automatic port selection
./jplaw2epub-server

# Specify port via flag
./jplaw2epub-server -port 8080

# Using environment variable
PORT=8080 ./jplaw2epub-server
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

## Docker Deployment

Build and run with Docker:

```sh
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

## Development

### Local Development

```bash
# Default (automatically finds available port)
go run main.go

# Specify port
go run main.go -port 8080

# Using environment variable
PORT=3000 go run main.go
```

### GraphQL Schema

The GraphQL schema is defined in `graphql/schema.graphqls`. To regenerate code after schema changes:

```sh
cd graphql
go run github.com/99designs/gqlgen generate
```

## Dependencies

- [jplaw2epub](https://github.com/ngs/jplaw2epub) - Core EPUB conversion library
- [jplaw-api-v2](https://go.ngs.io/jplaw-api-v2) - Japanese law API client
- [gqlgen](https://gqlgen.com/) - GraphQL code generation

## License

MIT License

Copyright © 2025 Atsushi Nagase