# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Copy go mod files from root
COPY go.mod go.sum ./
RUN go mod download

# Copy all source code
COPY . .

# Build the server binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o jplaw2epub-api .

# Final stage
FROM alpine:latest

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/jplaw2epub-api .

# Copy entrypoint script
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

# Expose port
EXPOSE 8080

# Set default PORT environment variable for Cloud Run
ENV PORT=8080

# Optional: Set default CORS origins (can be overridden at runtime)
# ENV CORS_ORIGINS=""

# Use entrypoint script to handle arguments
ENTRYPOINT ["./docker-entrypoint.sh"]

# Default command (can be overridden)
CMD []