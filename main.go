package main

import (
	"bytes"
	"encoding/base64"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/playground"
	jplaw "go.ngs.io/jplaw-api-v2"
	"go.ngs.io/jplaw2epub"

	"go.ngs.io/jplaw2epub-web-api/graphql"
)

func main() {
	portFlag := flag.String("port", "", "Port to listen on (default: find available port)")
	flag.Parse()

	port := determinePort(*portFlag)

	http.HandleFunc("/convert", convertHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/epubs/", epubsHandler)

	// GraphQL handlers.
	srv := handler.NewDefaultServer(graphql.NewExecutableSchema(graphql.Config{Resolvers: graphql.NewResolver()}))
	http.Handle("/graphql", srv)
	http.Handle("/graphiql", playground.Handler("GraphQL playground", "/graphql"))

	server := &http.Server{
		Addr:         ":" + port,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("Server starting on port %s", port)
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func determinePort(portFlag string) string {
	if portFlag != "" {
		return portFlag
	}
	if envPort := os.Getenv("PORT"); envPort != "" {
		return envPort
	}
	return findAvailablePort()
}

func findAvailablePort() string {
	listener, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		log.Fatalf("Failed to find available port: %v", err)
	}
	tcpAddr, ok := listener.Addr().(*net.TCPAddr)
	if !ok {
		log.Fatalf("Failed to get TCP address from listener")
	}
	port := strconv.Itoa(tcpAddr.Port)
	if err := listener.Close(); err != nil {
		log.Printf("Warning: failed to close listener: %v", err)
	}
	return port
}

func convertHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	contentType := r.Header.Get("Content-Type")
	if contentType != "application/xml" && contentType != "text/xml" {
		http.Error(w, "Content-Type must be application/xml or text/xml", http.StatusBadRequest)
		return
	}

	xmlData, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("Error reading request body: %v", err)
		http.Error(w, "Error reading request body", http.StatusBadRequest)
		return
	}

	if len(xmlData) == 0 {
		http.Error(w, "Empty request body", http.StatusBadRequest)
		return
	}

	xmlReader := bytes.NewReader(xmlData)
	book, err := jplaw2epub.CreateEPUBFromXMLFile(xmlReader)
	if err != nil {
		log.Printf("Error creating EPUB: %v", err)
		http.Error(w, fmt.Sprintf("Error creating EPUB: %v", err), http.StatusInternalServerError)
		return
	}

	var buf bytes.Buffer
	if _, err := book.WriteTo(&buf); err != nil {
		log.Printf("Error writing EPUB to buffer: %v", err)
		http.Error(w, "Error generating EPUB", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/epub+zip")
	w.Header().Set("Content-Disposition", "attachment; filename=\"law.epub\"")
	w.Header().Set("Content-Length", strconv.Itoa(buf.Len()))

	if _, err := buf.WriteTo(w); err != nil {
		log.Printf("Error writing response: %v", err)
		return
	}

	log.Printf("Successfully converted XML to EPUB (%d bytes)", buf.Len())
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"status":"ok","service":"jplaw2epub-server"}`)
}

func epubsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract ID from path: /epubs/{id}.
	path := strings.TrimPrefix(r.URL.Path, "/epubs/")
	if path == "" || path == "/" {
		http.Error(w, "Law ID is required", http.StatusBadRequest)
		return
	}

	// Remove any trailing slashes.
	lawID := strings.TrimSuffix(path, "/")

	log.Printf("Fetching law data for ID: %s", lawID)

	// Create API client.
	client := jplaw.NewClient()

	// Set up parameters to get XML format.
	xmlFormat := jplaw.ResponseFormatXml
	params := &jplaw.GetLawDataParams{
		LawFullTextFormat: &xmlFormat,
	}

	// Get law data with XML format.
	lawData, err := client.GetLawData(lawID, params)
	if err != nil {
		log.Printf("Error fetching law data for ID %s: %v", lawID, err)
		if strings.Contains(err.Error(), "404") {
			http.Error(w, "Law not found", http.StatusNotFound)
		} else {
			http.Error(w, fmt.Sprintf("Error fetching law data: %v", err), http.StatusInternalServerError)
		}
		return
	}

	// Extract XML content from response.
	xmlContent, err := extractXMLContent(lawData, lawID)
	if err != nil {
		log.Printf("Error extracting XML content for law ID %s: %v", lawID, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Convert XML to EPUB.
	xmlReader := bytes.NewReader(xmlContent)
	book, err := jplaw2epub.CreateEPUBFromXMLFile(xmlReader)
	if err != nil {
		log.Printf("Error creating EPUB for law ID %s: %v", lawID, err)
		http.Error(w, fmt.Sprintf("Error creating EPUB: %v", err), http.StatusInternalServerError)
		return
	}

	// Generate EPUB to buffer.
	var buf bytes.Buffer
	if _, err := book.WriteTo(&buf); err != nil {
		log.Printf("Error writing EPUB to buffer for law ID %s: %v", lawID, err)
		http.Error(w, "Error generating EPUB", http.StatusInternalServerError)
		return
	}

	// Set response headers.
	filename := fmt.Sprintf("%s.epub", lawID)
	w.Header().Set("Content-Type", "application/epub+zip")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
	w.Header().Set("Content-Length", strconv.Itoa(buf.Len()))

	// Write response.
	if _, err := buf.WriteTo(w); err != nil {
		log.Printf("Error writing response for law ID %s: %v", lawID, err)
		return
	}

	log.Printf("Successfully converted law ID %s to EPUB (%d bytes)", lawID, buf.Len())
}

func extractXMLContent(lawData *jplaw.LawDataResponse, lawID string) ([]byte, error) {
	if lawData.LawFullText == nil {
		return nil, fmt.Errorf("no law content in response")
	}

	xmlStr, ok := (*lawData.LawFullText).(string)
	if !ok {
		return nil, fmt.Errorf("invalid XML format in response")
	}

	// The XML is Base64 encoded, decode it.
	decodedXML, err := base64.StdEncoding.DecodeString(xmlStr)
	if err != nil {
		return nil, fmt.Errorf("error decoding XML content: %v", err)
	}

	// Remove <TmpRootTag> wrapper if present.
	xmlContent := string(decodedXML)
	if strings.HasPrefix(xmlContent, "<TmpRootTag>") {
		xmlContent = strings.TrimPrefix(xmlContent, "<TmpRootTag>")
		xmlContent = strings.TrimSuffix(xmlContent, "</TmpRootTag>")
	}

	log.Printf("Decoded XML content length for law ID %s: %d bytes", lawID, len(xmlContent))
	return []byte(xmlContent), nil
}
