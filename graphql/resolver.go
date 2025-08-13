package graphql

// This file will not be regenerated automatically.
//
// It serves as dependency injection for your app, add any dependencies you require here.

import (
	jplaw "go.ngs.io/jplaw-api-v2"
)

type Resolver struct {
	client *jplaw.Client
}

func NewResolver() *Resolver {
	return &Resolver{
		client: jplaw.NewClient(),
	}
}
