resource "aws_s3_bucket" "input" {
  bucket = "netflix-${var.env}-input"
}

resource "aws_s3_bucket" "output" {
  bucket = "netflix-${var.env}-output"
}

resource "aws_s3_bucket_policy" "output" {
  bucket = aws_s3_bucket.output.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "cloudfront.amazonaws.com" },
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.output.arn}/*",
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = var.cloudfront_distribution_arn
        }
      }
    }]
  })
}

output "output_bucket_domain" {
  value = aws_s3_bucket.output.bucket_regional_domain_name
}

output "input_bucket_arn" {
  value = aws_s3_bucket.input.arn
}

output "input_bucket_id" {
  value = aws_s3_bucket.input.id
}