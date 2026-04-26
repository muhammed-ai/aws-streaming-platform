provider "aws" {
  region = var.region
}

module "networking" {
  source = "../../modules/networking"
  env    = var.env
}

module "waf" {
  source = "../../modules/waf"
  env    = var.env
}

module "s3" {
  source                      = "../../modules/s3"
  env                         = var.env
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  depends_on                  = [module.cloudfront]
}

module "cloudfront" {
  source        = "../../modules/cloudfront"
  env           = var.env
  bucket_domain = "netflix-${var.env}-output.s3.amazonaws.com"
  web_acl_id    = module.waf.web_acl_id
}

module "dynamodb" {
  source = "../../modules/dynamodb"
  env    = var.env
}

module "lambda" {
  source              = "../../modules/lambda"
  env                 = var.env
  dynamodb_table_arn  = module.dynamodb.table_arn
  s3_input_bucket_arn = module.s3.input_bucket_arn
}

module "api" {
  source               = "../../modules/api_gateway"
  env                  = var.env
  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name
}

module "cognito" {
  source = "../../modules/cognito"
  env    = var.env
}

module "mediaconvert" {
  source            = "../../modules/mediaconvert"
  env               = var.env
  region            = var.region
  input_bucket_arn  = module.s3.input_bucket_arn
  input_bucket_id   = module.s3.input_bucket_id
  output_bucket_arn = "arn:aws:s3:::netflix-${var.env}-output"
  output_bucket_id  = "netflix-${var.env}-output"
}