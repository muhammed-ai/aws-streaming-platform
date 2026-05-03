# CloudFront domain — use this to stream videos e.g. https://<domain>/test-media-converter.m3u8
output "cloudfront_domain" {
  value = module.cloudfront.domain_name
}

# API Gateway endpoint — use this as the base URL for all API calls from the frontend
output "api_endpoint" {
  value = module.api.api_endpoint
}
