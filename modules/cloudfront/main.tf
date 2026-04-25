resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "netflix-oac-${var.env}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name              = var.bucket_domain
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  web_acl_id = var.web_acl_id

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.cdn.arn
}