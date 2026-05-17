variable "env" {}
variable "cloudfront_distribution_arn" {}

# Lambda IAM role ARN — granted read access to the output bucket for manifest proxy
variable "lambda_role_arn" {}
