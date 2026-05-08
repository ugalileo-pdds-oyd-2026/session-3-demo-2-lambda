output "invoke_url" {
  description = "APIGW HTTP API invoke URL — structurally equivalent to EC2 public_ip"
  value       = module.compute_lambda.invoke_url
}