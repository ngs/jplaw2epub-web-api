# jplaw2epub-web-api

Web API server for converting Japanese law documents to EPUB format.

This project provides REST and GraphQL APIs for:
- Converting Japanese Standard Law XML Schema to EPUB files
- Querying Japanese law data via GraphQL
- Fetching and converting laws by ID

## Installation

```sh
go install go.ngs.io/jplaw2epub-web-api/cmd/jplaw2epub-server@latest
```

Or build from source:

```sh
git clone https://github.com/ngs/jplaw2epub-web-api.git
cd jplaw2epub-web-api
go build -o jplaw2epub-server ./cmd/jplaw2epub-server
```

## Running the Server

```sh
# Use automatic port selection
jplaw2epub-server

# Specify port via flag
jplaw2epub-server -port 8080

# Specify port via environment variable
PORT=8080 jplaw2epub-server
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

## Docker Deployment

Build and run with Docker:

```sh
docker build -t jplaw2epub-server -f cmd/jplaw2epub-server/Dockerfile .
docker run -p 8080:8080 jplaw2epub-server
```

## Google Cloud Run Deployment

See [cmd/jplaw2epub-server/README.md](cmd/jplaw2epub-server/README.md) for Cloud Run deployment instructions.

## Development

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