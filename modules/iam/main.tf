resource "aws_iam_role" "lambda_role" {
  name = "netflix-lambda-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_lambda_function" "api" {
  function_name = "netflix-api-${var.env}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  # placeholder zip (empty file for now)
  filename = "${path.module}/lambda.zip"
}