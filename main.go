package main

import (
	"flag"
	"log"
	"net/http"
	"time"

	"github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/playground"

	"go.ngs.io/jplaw2epub-web-api/graphql"
	"go.ngs.io/jplaw2epub-web-api/handlers"
)

func main() {
	portFlag := flag.String("port", "", "Port to listen on (default: find available port)")
	corsOriginsFlag := flag.String("cors-origins", "", "Comma-separated list of allowed CORS origins (e.g., 'https://example.com,https://app.example.com')")
	flag.Parse()

	port := handlers.DeterminePort(*portFlag)
	allowedOrigins := handlers.ParseAllowedOrigins(*corsOriginsFlag)

	// Wrap handlers with CORS middleware.
	http.HandleFunc("/health", handlers.WithCORS(handlers.HealthHandler, allowedOrigins))

	// GraphQL handlers.
	srv := handler.NewDefaultServer(graphql.NewExecutableSchema(graphql.Config{Resolvers: graphql.NewResolver()}))
	http.Handle("/graphql", handlers.WithCORSHandler(srv, allowedOrigins))
	http.Handle("/graphiql", playground.Handler("GraphQL playground", "/graphql"))

	server := &http.Server{
		Addr:         ":" + port,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("Server starting on port %s", port)
	if len(allowedOrigins) > 0 {
		log.Printf("CORS enabled for origins: %v", allowedOrigins)
	} else {
		log.Printf("CORS disabled (no origins specified)")
	}
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
