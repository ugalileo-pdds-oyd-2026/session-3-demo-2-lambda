output "invoke_url" {
  description = "APIGW HTTP API invoke URL — structurally equivalent to EC2 public_ip"
  value       = aws_apigatewayv2_stage.this.invoke_url
}
