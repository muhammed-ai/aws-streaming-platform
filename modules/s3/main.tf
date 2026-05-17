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

# Block all public access — content is only accessible via CloudFront OAC
resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

# Bucket policy that allows only the CloudFront distribution to read from the output bucket
# The AWS:SourceArn condition ensures no other CloudFront distribution can access this bucket
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
