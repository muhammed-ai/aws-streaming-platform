variable "env" {}
variable "lambda_invoke_arn" {}
variable "lambda_function_name" {}

# Frontend CloudFront domain — added to CORS allow_origins so the browser can call the API
variable "frontend_domain" {}
