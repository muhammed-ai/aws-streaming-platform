resource "aws_wafv2_web_acl" "waf" {
  name  = "netflix-${var.env}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf"
    sampled_requests_enabled   = true
  }
}

output "web_acl_id" {
  value = aws_wafv2_web_acl.waf.arn
}