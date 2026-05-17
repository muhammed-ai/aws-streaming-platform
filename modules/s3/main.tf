# Input bucket — where raw video files are uploaded before transcoding
# S3 event notifications on this bucket trigger the MediaConvert Lambda
resource "aws_s3_bucket" "input" {
  bucket = "netflix-${var.env}-input"
}

# Output bucket — where MediaConvert writes the transcoded HLS files after processing
# This bucket is served privately through CloudFront — not publicly accessible directly
resource "aws_s3_bucket" "output" {
  bucket = "netflix-${var.env}-output"
}

# Block public ACLs and public access — role-based access via IAM and bucket policy still works
resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

# CORS configuration on the output bucket — required for HLS.js to fetch
# .m3u8 manifests and .ts segments cross-origin from the browser
resource "aws_s3_bucket_cors_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# Bucket policy — allows only the CloudFront distribution to read video files
# Lambda access is granted via IAM role policy, not bucket policy
resource "aws_s3_bucket_policy" "output" {
  bucket = aws_s3_bucket.output.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowCloudFront"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.output.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = var.cloudfront_distribution_arn
          }
        }
      },
      {
        Sid       = "AllowLambdaRead"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/netflix-lambda-role-${var.env}" }
        Action    = ["s3:GetObject", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.output.arn, "${aws_s3_bucket.output.arn}/*"]
      },
      {
        Sid       = "AllowMediaConvertWrite"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mediaconvert-role-${var.env}" }
        Action    = ["s3:PutObject"]
        Resource  = "${aws_s3_bucket.output.arn}/*"
      }
    ]
  })
}

# Used to get the current AWS account ID for constructing the Lambda role ARN
data "aws_caller_identity" "current" {}

# Exposes the output bucket's regional domain — used by CloudFront as the origin domain
output "output_bucket_domain" {
  value = aws_s3_bucket.output.bucket_regional_domain_name
}

# Exposes the input bucket ARN — used by Lambda and MediaConvert IAM policies
output "input_bucket_arn" {
  value = aws_s3_bucket.input.arn
}

# Exposes the input bucket ID (name) — used by the S3 event notification in the mediaconvert module
output "input_bucket_id" {
  value = aws_s3_bucket.input.id
}

# Exposes the output bucket ARN — used by Lambda IAM policy for manifest proxy
output "output_bucket_arn" {
  value = aws_s3_bucket.output.arn
}

# Exposes the output bucket name — used by Lambda env var for manifest proxy
output "output_bucket_id" {
  value = aws_s3_bucket.output.id
}
