.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: run
run: ## Run the server locally
	go run main.go

.PHONY: build
build: ## Build the binary
	go build -o jplaw2epub-api .

.PHONY: test
test: ## Run tests
	go test -v ./...

.PHONY: lint
lint: ## Run linter
	golangci-lint run

.PHONY: fmt
fmt: ## Format code
	goimports -w -local go.ngs.io/jplaw2epub-web-api .
	gofmt -w .

.PHONY: clean
clean: ## Clean build artifacts
	rm -f jplaw2epub-api
	go clean

.PHONY: deps
deps: ## Download dependencies
	go mod download
	go mod tidy

.PHONY: docker-build
docker-build: ## Build Docker image
	docker build -t jplaw2epub-api .

.PHONY: docker-run
docker-run: ## Run Docker container
	docker run -p 8080:8080 jplaw2epub-api

.PHONY: docker-run-cors
docker-run-cors: ## Run Docker container with CORS enabled for all origins
	docker run -p 8080:8080 jplaw2epub-api -cors-origins "*"

.PHONY: docker-compose-up
docker-compose-up: ## Run with docker-compose
	docker-compose up

.PHONY: docker-compose-dev
docker-compose-dev: ## Run development profile with docker-compose
	docker-compose --profile dev up

.PHONY: gqlgen
gqlgen: ## Generate GraphQL code
	cd graphql && go run github.com/99designs/gqlgen generate

.PHONY: install-tools
install-tools: ## Install development tools
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install golang.org/x/tools/cmd/goimports@latest
	go install github.com/99designs/gqlgen@latest

.PHONY: all
all: deps fmt lint test build ## Run all checks and build