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
FROM alpine:3.20

# Install required runtime dependencies  
# go-fitz v1.24.15 requires MuPDF 1.24.x
RUN apk --no-cache add ca-certificates libffi mupdf-libs && \
  ln -s /usr/lib/libmupdf.so.* /usr/lib/libmupdf.so && \
  # Set FZ_VERSION based on installed MuPDF version
  echo "export FZ_VERSION=$(ls /usr/lib/libmupdf.so.* | sed 's/.*\.so\.//' | head -1)" >> /etc/profile.d/fz_version.sh

# Set FZ_VERSION environment variable
ENV FZ_VERSION=1.24.2

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