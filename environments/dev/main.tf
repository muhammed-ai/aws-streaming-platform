provider "aws" {
  region = var.region
}

# Networking — creates the VPC, subnets, and internet gateway
module "networking" {
  source = "../../modules/networking"
  env    = var.env
}

# WAF — must be created before CloudFront since CloudFront needs the WAF ARN
module "waf" {
  source = "../../modules/waf"
  env    = var.env
}

# S3 — depends on CloudFront because the output bucket policy needs the CloudFront distribution ARN
# to restrict S3 access to only this distribution via OAC
module "s3" {
  source                      = "../../modules/s3"
  env                         = var.env
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  depends_on                  = [module.cloudfront]
}

# CloudFront — serves transcoded video from the S3 output bucket, protected by WAF
# Uses regional S3 domain required by OAC — format: bucket.s3.region.amazonaws.com
module "cloudfront" {
  source           = "../../modules/cloudfront"
  env              = var.env
  bucket_domain    = "netflix-${var.env}-output.s3.us-east-1.amazonaws.com"
  web_acl_id       = module.waf.web_acl_id
  cf_key_group_id  = var.cf_key_group_id
}

# DynamoDB — stores video metadata, created before Lambda since Lambda needs the table ARN for IAM policy
module "dynamodb" {
  source = "../../modules/dynamodb"
  env    = var.env
}

# Lambda — main API function, wired to DynamoDB and S3 via IAM policies
module "lambda" {
  source              = "../../modules/lambda"
  env                 = var.env
  dynamodb_table_arn  = module.dynamodb.table_arn
  s3_input_bucket_arn = module.s3.input_bucket_arn
  cloudfront_domain   = "https://${module.cloudfront.domain_name}"
  cf_key_pair_id      = var.cf_key_pair_id
  cf_private_key      = var.cf_private_key
}

# API Gateway — HTTP API that routes all requests to the Lambda function
module "api" {
  source               = "../../modules/api_gateway"
  env                  = var.env
  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name
}

# Cognito — user authentication pool for the frontend
module "cognito" {
  source = "../../modules/cognito"
  env    = var.env
}

# MediaConvert — transcoding pipeline triggered automatically when videos are uploaded to S3 input bucket
# output_bucket_arn and output_bucket_id are passed directly to avoid a circular dependency with the S3 module
module "mediaconvert" {
  source            = "../../modules/mediaconvert"
  env               = var.env
  region            = var.region
  input_bucket_arn  = module.s3.input_bucket_arn
  input_bucket_id   = module.s3.input_bucket_id
  output_bucket_arn = "arn:aws:s3:::netflix-${var.env}-output"
  output_bucket_id  = "netflix-${var.env}-output"
}
