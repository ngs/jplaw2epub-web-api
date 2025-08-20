package handlers

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"

	"go.ngs.io/jplaw2epub"
)

func ConvertHandler(w http.ResponseWriter, r *http.Request) {
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
