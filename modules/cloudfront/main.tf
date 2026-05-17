# Origin Access Control — allows CloudFront to securely access the private S3 output bucket
# Without this, S3 would block all CloudFront requests with a 403
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "netflix-oac-${var.env}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution — serves transcoded video content globally from the S3 output bucket
# Acts as the CDN layer between users and S3, reducing latency and protecting the origin
resource "aws_cloudfront_distribution" "cdn" {
  # Points to the S3 output bucket where MediaConvert writes transcoded HLS files
  origin {
    domain_name              = var.bucket_domain
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled = true

  default_cache_behavior {
    target_origin_id = "s3-origin"

    # Forces HTTPS — redirects any HTTP requests to HTTPS
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      # CloudFront signed URL query strings must be forwarded so CloudFront can verify them
      query_string = true
      cookies {
        forward = "none"
      }
    }

    # Restricts access to signed URLs only — unsigned requests get a 403
    # The key group contains the public key CloudFront uses to verify Lambda's signatures
    trusted_key_groups = [var.cf_key_group_id]
  }

  # No geo-blocking — content is available globally
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Attaches the WAF Web ACL to filter malicious traffic before it reaches the origin
  web_acl_id = var.web_acl_id

  # Uses the default CloudFront certificate — replace with ACM cert for a custom domain
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Exposes the CloudFront domain name — this is the URL users use to stream videos
output "domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

# Exposes the distribution ARN — used by the S3 bucket policy to restrict access to only this distribution
output "distribution_arn" {
  value = aws_cloudfront_distribution.cdn.arn
}
