# Creates the HTTP API — this is the entry point for all frontend API calls
resource "aws_apigatewayv2_api" "api" {
  name          = "netflix-api-${var.env}"
  protocol_type = "HTTP"

  # CORS configuration — allows the frontend CloudFront domain to call the API from the browser
  cors_configuration {
    allow_origins = [var.frontend_domain, "http://localhost:3000"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

# Wires API Gateway to Lambda using AWS_PROXY — forwards the full request to Lambda and returns its response directly
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arn
  payload_format_version = "2.0"
}

# Catch-all route — any path/method that hits the API gets forwarded to the Lambda integration
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Auto-deploy stage — automatically deploys any changes to the API without a manual deployment step
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# Grants API Gateway permission to invoke the Lambda function
# source_arn restricts it to only this API's routes — prevents other APIs from invoking the same Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# Exposes the live API URL as an output so other modules or the user can reference it
output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}
