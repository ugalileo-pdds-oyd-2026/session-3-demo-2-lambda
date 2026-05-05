//go:build lambda

package main

import (
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"
)

// main wraps the shared http.Handler with the AWS Lambda HTTP adapter.
// The adapter translates API Gateway v2 (HTTP API) payload format 2.0
// events into standard http.Request / http.ResponseWriter calls, so
// buildHandler() in main.go requires zero changes for Lambda.
func main() {
	lambda.Start(httpadapter.NewV2(buildHandler()).ProxyWithContext)
}
