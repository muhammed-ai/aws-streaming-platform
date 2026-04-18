resource "aws_apigatewayv2_api" "api" {
  name          = "netflix-api-${var.env}"
  protocol_type = "HTTP"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}