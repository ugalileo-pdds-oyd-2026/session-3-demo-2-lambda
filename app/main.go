package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
)

// buildHandler registers all application routes and returns the configured mux.
// This function is the single source of truth for application behaviour —
// identical across EC2, Lambda, ECS and EKS. The entrypoint (server.go or
// lambda.go) determines how the handler is served.
func buildHandler() http.Handler {
	compute := os.Getenv("COMPUTE_TYPE")
	if compute == "" {
		compute = "unknown"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "ok",
			"compute": compute,
		})
	})

	mux.HandleFunc("/echo", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var payload map[string]interface{}
		json.Unmarshal(body, &payload)
		if payload == nil {
			payload = map[string]interface{}{}
		}
		payload["compute"] = compute
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(payload)
	})

	return mux
}
