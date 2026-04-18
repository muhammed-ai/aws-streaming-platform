resource "aws_s3_bucket" "input" {
  bucket = "netflix-${var.env}-input"
}

resource "aws_s3_bucket" "output" {
  bucket = "netflix-${var.env}-output"
}

output "output_bucket_domain" {
  value = aws_s3_bucket.output.bucket_regional_domain_name
}