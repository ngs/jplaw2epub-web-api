package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// responseWriter wraps http.ResponseWriter to capture status code and size.
type responseWriter struct {
	http.ResponseWriter
	status int
	size   int
}

func (rw *responseWriter) WriteHeader(status int) {
	rw.status = status
	rw.ResponseWriter.WriteHeader(status)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	size, err := rw.ResponseWriter.Write(b)
	rw.size += size
	return size, err
}

// ApacheLoggerMiddleware logs HTTP requests in Apache Combined Log Format.
// Format: remote_addr - remote_user [time_local] "request" status size "referer" "user_agent".
// Example: 127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.08 [en] (Win98; I ;Nav)".
func ApacheLoggerMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap the ResponseWriter to capture status and size.
		wrapped := &responseWriter{
			ResponseWriter: w,
			status:         http.StatusOK, // Default to 200 if not set.
		}

		// Process request.
		next.ServeHTTP(wrapped, r)

		// Log in Apache format.
		logApacheFormat(r, wrapped, time.Since(start))
	})
}

func logApacheFormat(r *http.Request, rw *responseWriter, _ time.Duration) {
	// Get remote address.
	remoteAddr := r.RemoteAddr
	if xForwardedFor := r.Header.Get("X-Forwarded-For"); xForwardedFor != "" {
		// Use the first IP in X-Forwarded-For if present.
		remoteAddr = strings.Split(xForwardedFor, ",")[0]
	} else if xRealIP := r.Header.Get("X-Real-IP"); xRealIP != "" {
		remoteAddr = xRealIP
	}

	// Get remote user (from Basic Auth if present).
	remoteUser := "-"
	if user, _, ok := r.BasicAuth(); ok && user != "" {
		remoteUser = user
	}

	// Format time in Apache format: [day/month/year:hour:minute:second zone].
	timeLocal := time.Now().Format("[02/Jan/2006:15:04:05 -0700]")

	// Build request line.
	requestLine := fmt.Sprintf("%s %s %s", r.Method, r.RequestURI, r.Proto)

	// Get referer.
	referer := r.Header.Get("Referer")
	if referer == "" {
		referer = "-"
	} else {
		referer = fmt.Sprintf("%q", referer)
	}

	// Get user agent.
	userAgent := r.Header.Get("User-Agent")
	if userAgent == "" {
		userAgent = "-"
	} else {
		userAgent = fmt.Sprintf("%q", userAgent)
	}

	// Format size (0 becomes "-" in Apache format).
	size := fmt.Sprintf("%d", rw.size)
	if rw.size == 0 {
		size = "-"
	}

	// Log in Apache Combined Log Format.
	log.Printf("%s - %s %s \"%s\" %d %s %s %s",
		remoteAddr,
		remoteUser,
		timeLocal,
		requestLine,
		rw.status,
		size,
		referer,
		userAgent,
	)
}

// GraphQLRequest represents a GraphQL request payload.
type GraphQLRequest struct {
	Query         string                 `json:"query"`
	OperationName string                 `json:"operationName,omitempty"`
	Variables     map[string]interface{} `json:"variables,omitempty"`
}

// extractGraphQLInfo extracts GraphQL operation details from the request.
func extractGraphQLInfo(r *http.Request) string {
	if r.Method != "POST" || !strings.Contains(r.URL.Path, "graphql") {
		return ""
	}

	// Read body.
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		return ""
	}
	// Restore body for downstream handlers.
	r.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))

	// Parse GraphQL request.
	var gqlReq GraphQLRequest
	if err := json.Unmarshal(bodyBytes, &gqlReq); err != nil {
		return ""
	}

	// Extract operation type and name.
	operationType := extractOperationType(gqlReq.Query)
	operationName := gqlReq.OperationName
	if operationName == "" {
		operationName = extractOperationName(gqlReq.Query)
	}

	// Build GraphQL info string.
	var info []string
	if operationType != "" {
		info = append(info, operationType)
	}
	if operationName != "" {
		info = append(info, operationName)
	}

	// Add variables count if present.
	if len(gqlReq.Variables) > 0 {
		info = append(info, fmt.Sprintf("%d vars", len(gqlReq.Variables)))
	}

	if len(info) > 0 {
		return "[" + strings.Join(info, " ") + "]"
	}
	return ""
}

// extractOperationType extracts the operation type (query/mutation/subscription) from GraphQL query.
func extractOperationType(query string) string {
	query = strings.TrimSpace(query)

	// Check for shorthand query (starts with {).
	if strings.HasPrefix(query, "{") {
		return "query"
	}

	// Look for operation type keyword.
	operationPattern := regexp.MustCompile(`^\s*(query|mutation|subscription)\b`)
	matches := operationPattern.FindStringSubmatch(query)
	if len(matches) > 1 {
		return matches[1]
	}

	return ""
}

// extractOperationName extracts the operation name from GraphQL query.
func extractOperationName(query string) string {
	// Pattern to match operation name after query/mutation/subscription.
	// Examples: "query GetLaws {", "mutation CreateItem(", "query {" (anonymous).
	pattern := regexp.MustCompile(`^\s*(?:query|mutation|subscription)\s+([A-Za-z][A-Za-z0-9_]*)\s*[({]`)
	matches := pattern.FindStringSubmatch(query)
	if len(matches) > 1 {
		return matches[1]
	}

	// For shorthand queries, try to extract the first field name.
	if strings.HasPrefix(strings.TrimSpace(query), "{") {
		fieldPattern := regexp.MustCompile(`{\s*([A-Za-z][A-Za-z0-9_]*)\s*[({]`)
		matches = fieldPattern.FindStringSubmatch(query)
		if len(matches) > 1 {
			return matches[1]
		}
	}

	return ""
}

// ApacheLoggerWithDuration includes response time at the end (Apache with %D).
func ApacheLoggerWithDuration(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Extract GraphQL info before processing.
		graphqlInfo := extractGraphQLInfo(r)

		// Wrap the ResponseWriter to capture status and size.
		wrapped := &responseWriter{
			ResponseWriter: w,
			status:         http.StatusOK,
		}

		// Process request.
		next.ServeHTTP(wrapped, r)

		// Log with duration.
		duration := time.Since(start)
		logApacheFormatWithDuration(r, wrapped, duration, graphqlInfo)
	})
}

func logApacheFormatWithDuration(r *http.Request, rw *responseWriter, duration time.Duration, graphqlInfo string) {
	// Get remote address.
	remoteAddr := r.RemoteAddr
	if xForwardedFor := r.Header.Get("X-Forwarded-For"); xForwardedFor != "" {
		remoteAddr = strings.Split(xForwardedFor, ",")[0]
	} else if xRealIP := r.Header.Get("X-Real-IP"); xRealIP != "" {
		remoteAddr = xRealIP
	}

	// Get remote user.
	remoteUser := "-"
	if user, _, ok := r.BasicAuth(); ok && user != "" {
		remoteUser = user
	}

	// Format time.
	timeLocal := time.Now().Format("[02/Jan/2006:15:04:05 -0700]")

	// Build request line, optionally including GraphQL info.
	requestLine := fmt.Sprintf("%s %s %s", r.Method, r.RequestURI, r.Proto)
	if graphqlInfo != "" {
		requestLine = fmt.Sprintf("%s %s %s %s", r.Method, r.RequestURI, r.Proto, graphqlInfo)
	}

	// Get referer.
	referer := r.Header.Get("Referer")
	if referer == "" {
		referer = "-"
	} else {
		referer = fmt.Sprintf("%q", referer)
	}

	// Get user agent.
	userAgent := r.Header.Get("User-Agent")
	if userAgent == "" {
		userAgent = "-"
	} else {
		userAgent = fmt.Sprintf("%q", userAgent)
	}

	// Format size.
	size := fmt.Sprintf("%d", rw.size)
	if rw.size == 0 {
		size = "-"
	}

	// Duration in microseconds (Apache %D format).
	durationMicros := duration.Microseconds()

	// Log in Apache Combined Log Format with duration.
	log.Printf("%s - %s %s \"%s\" %d %s %s %s %dµs",
		remoteAddr,
		remoteUser,
		timeLocal,
		requestLine,
		rw.status,
		size,
		referer,
		userAgent,
		durationMicros,
	)
}
