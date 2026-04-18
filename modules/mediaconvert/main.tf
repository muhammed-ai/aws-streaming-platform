resource "aws_iam_role" "mediaconvert" {
  name = "mediaconvert-role-${var.env}"

  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "mediaconvert.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}