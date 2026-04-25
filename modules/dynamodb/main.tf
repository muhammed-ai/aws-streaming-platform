resource "aws_dynamodb_table" "videos" {
  name         = "videos-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "video_id"

  attribute {
    name = "video_id"
    type = "S"
  }
}

output "table_arn" {
  value = aws_dynamodb_table.videos.arn
}