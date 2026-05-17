variable "env" {}
variable "dynamodb_table_arn" {}
variable "s3_input_bucket_arn" {}

# CloudFront domain for building signed streaming URLs — e.g. https://xxxx.cloudfront.net
variable "cloudfront_domain" {}

# CloudFront key pair ID — created in AWS Console under CloudFront → Key management
variable "cf_key_pair_id" {}

# CloudFront private key PEM string — store in SSM and pass in via tfvars or CI secret
variable "cf_private_key" {
  sensitive = true
}

# Output bucket ARN — Lambda needs read access to fetch manifests for the proxy endpoint
variable "s3_output_bucket_arn" {}
