variable "env" {}
variable "region" {}
variable "input_bucket_arn" {}
variable "input_bucket_id" {}
variable "output_bucket_arn" {}
variable "output_bucket_id" {}

# DynamoDB table ARN — used by the on-complete Lambda IAM policy
variable "dynamodb_table_arn" {}

# DynamoDB table name — passed as env var to the on-complete Lambda
variable "dynamodb_table_name" {}
