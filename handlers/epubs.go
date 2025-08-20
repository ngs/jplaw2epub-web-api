package handlers

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"

	jplaw "go.ngs.io/jplaw-api-v2"
	"go.ngs.io/jplaw2epub"
)

func EpubsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	path := strings.TrimPrefix(r.URL.Path, "/epubs/")
	if path == "" || path == "/" {
		http.Error(w, "Law ID is required", http.StatusBadRequest)
		return
	}

	lawIdOrNumOrRevisionId := strings.TrimSuffix(path, "/")

	log.Printf("Fetching law data for ID: %s", lawIdOrNumOrRevisionId)

	client := jplaw.NewClient()

	xmlFormat := jplaw.ResponseFormatXml
	params := &jplaw.GetLawDataParams{
		LawFullTextFormat: &xmlFormat,
	}

	lawData, err := client.GetLawData(lawIdOrNumOrRevisionId, params)
	if err != nil {
		log.Printf("Error fetching law data for ID %s: %v", lawIdOrNumOrRevisionId, err)
		if strings.Contains(err.Error(), "404") {
			http.Error(w, "Law not found", http.StatusNotFound)
		} else {
			http.Error(w, fmt.Sprintf("Error fetching law data: %v", err), http.StatusInternalServerError)
		}
		return
	}

	xmlContent, err := extractXMLContent(lawData, lawIdOrNumOrRevisionId)
	if err != nil {
		log.Printf("Error extracting XML content for law ID %s: %v", lawIdOrNumOrRevisionId, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	xmlReader := bytes.NewReader(xmlContent)
	options := &jplaw2epub.EPUBOptions{}

	idComponents := strings.Split(lawIdOrNumOrRevisionId, "_")
	if len(idComponents) == 3 {
		options.RevisionID = lawIdOrNumOrRevisionId
		options.APIClient = client
	}

	fmt.Println(options)

	book, err := jplaw2epub.CreateEPUBFromXMLFileWithOptions(xmlReader, options)
	if err != nil {
		log.Printf("Error creating EPUB for law ID %s: %v", lawIdOrNumOrRevisionId, err)
		http.Error(w, fmt.Sprintf("Error creating EPUB: %v", err), http.StatusInternalServerError)
		return
	}

	var buf bytes.Buffer
	if _, err := book.WriteTo(&buf); err != nil {
		log.Printf("Error writing EPUB to buffer for law ID %s: %v", lawIdOrNumOrRevisionId, err)
		http.Error(w, "Error generating EPUB", http.StatusInternalServerError)
		return
	}

	filename := fmt.Sprintf("%s.epub", lawIdOrNumOrRevisionId)
	w.Header().Set("Content-Type", "application/epub+zip")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
	w.Header().Set("Content-Length", strconv.Itoa(buf.Len()))

	if _, err := buf.WriteTo(w); err != nil {
		log.Printf("Error writing response for law ID %s: %v", lawIdOrNumOrRevisionId, err)
		return
	}

	log.Printf("Successfully converted law ID %s to EPUB (%d bytes)", lawIdOrNumOrRevisionId, buf.Len())
}

func extractXMLContent(lawData *jplaw.LawDataResponse, lawID string) ([]byte, error) {
	if lawData.LawFullText == nil {
		return nil, fmt.Errorf("no law content in response")
	}

	xmlStr, ok := (*lawData.LawFullText).(string)
	if !ok {
		return nil, fmt.Errorf("invalid XML format in response")
	}

	decodedXML, err := base64.StdEncoding.DecodeString(xmlStr)
	if err != nil {
		return nil, fmt.Errorf("error decoding XML content: %v", err)
	}

	xmlContent := string(decodedXML)
	if strings.HasPrefix(xmlContent, "<TmpRootTag>") {
		xmlContent = strings.TrimPrefix(xmlContent, "<TmpRootTag>")
		xmlContent = strings.TrimSuffix(xmlContent, "</TmpRootTag>")
	}

	log.Printf("Decoded XML content length for law ID %s: %d bytes", lawID, len(xmlContent))
	return []byte(xmlContent), nil
}
