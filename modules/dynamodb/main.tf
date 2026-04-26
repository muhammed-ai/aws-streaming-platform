# DynamoDB table for storing video metadata (title, S3 key, status, etc.)
# PAY_PER_REQUEST means no capacity planning needed — scales automatically with traffic
resource "aws_dynamodb_table" "videos" {
  name         = "videos-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "video_id"

  # Primary key — unique identifier for each video record
  attribute {
    name = "video_id"
    type = "S"
  }
}

# Exposes the table ARN — used by the Lambda IAM policy to scope DynamoDB access to this table only
output "table_arn" {
  value = aws_dynamodb_table.videos.arn
}
