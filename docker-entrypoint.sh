#!/bin/sh
set -e

# Build command line arguments
ARGS=""

# Add port flag if PORT environment variable is set and not default
if [ -n "$PORT" ] && [ "$PORT" != "8080" ]; then
    ARGS="$ARGS -port $PORT"
fi

# Add cors-origins flag if CORS_ORIGINS environment variable is set
if [ -n "$CORS_ORIGINS" ]; then
    ARGS="$ARGS -cors-origins \"$CORS_ORIGINS\""
fi

# Parse docker run arguments for cors-origins flag
for arg in "$@"; do
    case $arg in
        -cors-origins=*)
            CORS_VALUE="${arg#*=}"
            ARGS="$ARGS -cors-origins \"$CORS_VALUE\""
            shift
            ;;
        -cors-origins)
            if [ -n "$2" ]; then
                ARGS="$ARGS -cors-origins \"$2\""
                shift 2
            else
                echo "Error: -cors-origins requires a value"
                exit 1
            fi
            ;;
        -port=*)
            PORT_VALUE="${arg#*=}"
            ARGS="$ARGS -port $PORT_VALUE"
            shift
            ;;
        -port)
            if [ -n "$2" ]; then
                ARGS="$ARGS -port $2"
                shift 2
            else
                echo "Error: -port requires a value"
                exit 1
            fi
            ;;
        *)
            # Keep other arguments as-is
            ;;
    esac
done

# If no arguments passed, start with default configuration
if [ $# -eq 0 ]; then
    echo "Starting jplaw2epub-api with args: $ARGS"
    eval "./jplaw2epub-api $ARGS"
else
    # Pass through all arguments if any non-flag arguments are provided
    echo "Starting jplaw2epub-api with custom arguments: $*"
    exec "./jplaw2epub-api" "$@"
fi