# CloudFront domain — use this to stream videos e.g. https://<domain>/test-media-converter.m3u8
output "cloudfront_domain" {
  value = module.cloudfront.domain_name
}

# API Gateway endpoint — use this as the base URL for all API calls from the frontend
output "api_endpoint" {
  value = module.api.api_endpoint
}

# Frontend CloudFront URL — open this in your browser to access the UI
output "frontend_url" {
  value = module.frontend.frontend_domain
}

# Frontend S3 bucket — GitHub Actions syncs HTML/JS/CSS here after every deploy
output "frontend_bucket" {
  value = module.frontend.frontend_bucket
}

# Frontend CloudFront distribution ID — used to invalidate cache after frontend deploy
output "frontend_distribution_id" {
  value = module.frontend.frontend_distribution_id
}
