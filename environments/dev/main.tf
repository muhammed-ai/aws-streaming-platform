provider "aws" {
  region = var.region
}

module "networking" {
  source = "../../modules/networking"
  env    = var.env
}

module "s3" {
  source = "../../modules/s3"
  env    = var.env
}

module "waf" {
  source = "../../modules/waf"
  env    = var.env
}

module "cloudfront" {
  source        = "../../modules/cloudfront"
  bucket_domain = module.s3.output_bucket_domain
  web_acl_id    = module.waf.web_acl_id
}

module "lambda" {
  source = "../../modules/lambda"
  env    = var.env
}

module "api" {
  source = "../../modules/api_gateway"
  env    = var.env
}

module "dynamodb" {
  source = "../../modules/dynamodb"
  env    = var.env
}

module "cognito" {
  source = "../../modules/cognito"
  env    = var.env
}

module "mediaconvert" {
  source = "../../modules/mediaconvert"
  env    = var.env
}