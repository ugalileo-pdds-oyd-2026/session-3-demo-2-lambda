# Session 3 — Demo 2: Lambda + API Gateway

A Go HTTP service deployed to AWS Lambda via API Gateway v2, provisioned with Terraform. The same application handler used in previous demos runs here without modification — only the entrypoint changes.

## What students learn

- How Go build tags select the Lambda entrypoint vs. the plain HTTP server at compile time, keeping business logic DRY across compute types
- Why the Lambda custom runtime requires a binary named `bootstrap` and how `provided.al2023` works
- How `aws-lambda-go-api-proxy` bridges standard `net/http` handlers to Lambda events without rewriting the handler
- How API Gateway v2 (HTTP API) fronts a Lambda function and translates HTTP requests into Lambda events
- Why `source_code_hash` is required to detect handler changes when the zip filename stays the same
- Why `aws_lambda_permission` is needed separately from the IAM execution role — and what happens when you forget it

## Project structure

```
.
├── app/
│   ├── main.go       # shared handler — /health and /echo routes (unchanged across compute types)
│   ├── lambda.go     # Lambda entrypoint, activated by -tags lambda
│   ├── server.go     # plain HTTP entrypoint, excluded by -tags lambda
│   ├── go.mod
│   └── go.sum
└── infra/
    ├── provider.tf               # AWS provider, region us-west-2
    ├── variables.tf              # root-level input variables
    ├── outputs.tf                # exposes invoke_url from the module
    ├── main.tf                   # calls the compute_lambda module
    ├── envs/
    │   └── dev/
    │       └── dev.tfvars        # environment values: name, environment, memory_size
    └── modules/
        └── compute_lambda/
            ├── variables.tf      # module inputs: environment, name, memory_size
            ├── outputs.tf        # invoke_url output
            └── main.tf           # IAM role, Lambda function, API Gateway v2, permission
```

## Prerequisites

- [Go 1.22+](https://go.dev/dl/)
- [Terraform 1.6+](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) with credentials configured (`aws configure` or environment variables)
- `zip` CLI available

## Demo workflow

### 1. Understand the build tag switch

Open `app/lambda.go` and `app/server.go` side by side. Notice the build constraints at the top of each file:

```go
// lambda.go
//go:build lambda

// server.go
//go:build !lambda
```

`-tags lambda` activates `lambda.go` and excludes `server.go` at compile time. `main.go` compiles in both cases — unchanged. This is what keeps the handler DRY across EC2, Lambda, and every other compute type.

### 2. Build the Lambda binary

Lambda's `provided.al2023` custom runtime looks for a binary named exactly `bootstrap`. Any other name and Lambda won't find the handler.

```bash
cd app
go mod tidy
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda -o bootstrap .
ls -lh bootstrap
zip app.zip bootstrap
ls -lh app.zip
```

### 3. Explore `lambda.go`

```go
//go:build lambda

package main

import (
    "github.com/aws/aws-lambda-go/lambda"
    "github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"
)

func main() {
    lambda.Start(httpadapter.NewV2(buildHandler()).ProxyWithContext)
}
```

`httpadapter.NewV2` translates API Gateway v2 payload format 2.0 events into standard `http.Request`/`http.ResponseWriter` calls. `buildHandler()` never knows it's inside Lambda — it sees a normal HTTP request.

### 4. Review the Terraform module

The `compute_lambda` module creates eight resources in this order:

| Resource | Purpose |
|---|---|
| `aws_iam_role.lambda` | Execution role — Lambda assumes this |
| `aws_iam_role_policy_attachment.basic` | Grants CloudWatch Logs write access (`AWSLambdaBasicExecutionRole`) |
| `aws_lambda_function.this` | The function itself — `provided.al2023`, `arm64` |
| `aws_apigatewayv2_api.this` | HTTP API — the public entry point |
| `aws_apigatewayv2_integration.this` | Wires APIGW to the Lambda function via `AWS_PROXY` |
| `aws_apigatewayv2_route.health` | `GET /health` route |
| `aws_apigatewayv2_route.echo` | `POST /echo` route |
| `aws_apigatewayv2_stage.this` | `$default` stage with `auto_deploy = true` |
| `aws_lambda_permission.apigw` | Allows API Gateway to invoke the function |

Note `source_code_hash` on the Lambda function:

```hcl
source_code_hash = filebase64sha256("${path.module}/../../../app/app.zip")
```

Without it, rebuilding the zip produces no diff in Terraform — the filename didn't change. The hash detects content changes and forces a redeploy.

Note `aws_lambda_permission`. The IAM role controls what the function can do outbound. This permission controls who can invoke the function inbound. They are separate. Missing it results in a 403 from API Gateway even when routes and integration are correct.

### 5. Initialize and apply

```bash
cd ../infra
terraform init
terraform plan -var-file=envs/dev/dev.tfvars
terraform apply -var-file=envs/dev/dev.tfvars
```

Expected output:

```
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:

invoke_url = "https://<id>.execute-api.us-west-2.amazonaws.com"
```

Verify the function is active:

```bash
aws lambda get-function \
  --function-name demo-lambda-dev \
  --query '{FunctionArn:Configuration.FunctionArn,State:Configuration.State}'
```

### 6. Test the endpoints

```bash
INVOKE_URL=$(terraform output -raw invoke_url)

curl ${INVOKE_URL}/health
```

Expected output:

```json
{"compute":"lambda","status":"ok"}
```

```bash
curl -X POST ${INVOKE_URL}/echo \
  -H "Content-Type: application/json" \
  -d '{"message":"hello"}'
```

Expected output:

```json
{"compute":"lambda","message":"hello"}
```

The `invoke_url` plays the same role as `public_ip` in the EC2 demo — same curl commands, same responses, different infrastructure underneath.

### 7. Clean up

```bash
terraform destroy -var-file=envs/dev/dev.tfvars
```

## Next steps — CI/CD with GitHub Actions

The workflow below automates the full build-and-deploy cycle on every pull request. It builds the binary, applies Terraform, and posts the live invoke URL as a PR comment so reviewers can test the endpoint directly.

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  pull_request:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write

    env:
      AWS_REGION: us-west-2

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version-file: app/go.mod
          cache-dependency-path: app/go.sum

      - name: Build
        working-directory: app
        run: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda -o bootstrap .

      - name: Zip binary
        working-directory: app
        run: zip app.zip bootstrap

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.6"

      - name: Terraform Init
        working-directory: infra
        run: terraform init

      - name: Terraform Format Check
        working-directory: infra
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        working-directory: infra
        run: terraform validate

      - name: Terraform Apply
        working-directory: infra
        run: terraform apply -auto-approve -var-file=envs/dev/dev.tfvars

      - name: Get invoke URL
        id: tf_output
        working-directory: infra
        run: echo "invoke_url=$(terraform output -raw invoke_url)" >> "$GITHUB_OUTPUT"

      - name: Comment on PR
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### Deployment ready\n\n${{ steps.tf_output.outputs.invoke_url }}`,
            })
```

Things to notice in this workflow:

| Point | Where |
|---|---|
| `go-version-file: app/go.mod` — reads Go version from source, no hardcoded string | Set up Go |
| `go.sum` is committed — no `go mod tidy` needed in CI | Build step |
| `terraform apply -auto-approve` — this pipeline **deploys**, it does not just plan | Terraform Apply |
| `terraform output -raw invoke_url` → `GITHUB_OUTPUT` — wires the URL into the comment | Get invoke URL |
| PR comment posts the live endpoint — reviewer can `curl` it directly | Comment on PR |

Add these secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM key with Lambda, API Gateway, IAM access |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret |

## Expected outcomes

By the end of this demo, students should be able to:

1. Compile a Go binary for Lambda's ARM64 custom runtime using build tags, without changing shared handler code
2. Explain why the binary must be named `bootstrap` for `provided.al2023`
3. Describe how `httpadapter.NewV2` lets a standard `net/http` handler run inside Lambda
4. Identify the role of each API Gateway v2 resource in the chain from HTTP request to Lambda invocation
5. Explain why `source_code_hash` is necessary for Terraform to detect handler changes
6. Distinguish between the Lambda IAM execution role and the `aws_lambda_permission` resource, and explain what breaks when the permission is missing
