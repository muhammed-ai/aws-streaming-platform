# Policy that allows GitHub Actions to deploy the frontend —
# upload files to the frontend S3 bucket and invalidate the CloudFront cache
resource "aws_iam_policy" "frontend_deploy" {
  name        = "netflix-frontend-deploy-${var.env}"
  description = "Allows CI to sync frontend files to S3 and invalidate CloudFront"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::netflix-${var.env}-frontend",
          "arn:aws:s3:::netflix-${var.env}-frontend/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["cloudfront:CreateInvalidation"],
        Resource = "*"
      }
    ]
  })
}

# Attach the frontend deploy policy to the GitHub Actions OIDC role
# The role name must match what was created when OIDC was set up
resource "aws_iam_role_policy_attachment" "frontend_deploy" {
  role       = var.github_actions_role_name
  policy_arn = aws_iam_policy.frontend_deploy.arn
}
