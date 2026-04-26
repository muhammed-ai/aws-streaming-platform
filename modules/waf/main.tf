# WAF Web ACL — sits in front of CloudFront and filters malicious traffic before it reaches the origin
# scope = CLOUDFRONT means it must be deployed in us-east-1 regardless of the app region
resource "aws_wafv2_web_acl" "waf" {
  name  = "netflix-${var.env}-waf"
  scope = "CLOUDFRONT"

  # Default action is allow — add managed rule groups here to block common threats (SQLi, XSS, etc.)
  default_action {
    allow {}
  }

  # Enables CloudWatch metrics and request sampling for monitoring and debugging WAF rules
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf"
    sampled_requests_enabled   = true
  }
}

# Exposes the WAF ARN — passed to CloudFront as web_acl_id to attach the WAF to the distribution
output "web_acl_id" {
  value = aws_wafv2_web_acl.waf.arn
}
