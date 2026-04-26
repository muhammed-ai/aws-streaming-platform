provider "aws" {
  region = "us-east-1"
}

# S3 bucket for storing Terraform state files remotely
# Must be applied once before any environment — all environments share this bucket
resource "aws_s3_bucket" "tf_state" {
  bucket = "netflix-tf-state-12345-unique"
}

# DynamoDB table for Terraform state locking
# Prevents two terraform applies from running simultaneously and corrupting the state file
resource "aws_dynamodb_table" "locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  # LockID is the key Terraform uses to acquire and release the state lock
  attribute {
    name = "LockID"
    type = "S"
  }
}
