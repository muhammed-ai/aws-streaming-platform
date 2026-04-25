resource "aws_iam_role" "lambda_role" {
  name = "netflix-lambda-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamodb" {
  name = "lambda-dynamodb-${var.env}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan", "dynamodb:Query"],
      Resource = var.dynamodb_table_arn
    }]
  })
}

resource "aws_iam_role_policy" "s3" {
  name = "lambda-s3-${var.env}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject", "s3:ListBucket"],
      Resource = [var.s3_input_bucket_arn, "${var.s3_input_bucket_arn}/*"]
    }]
  })
}

resource "aws_lambda_function" "api" {
  function_name = "netflix-api-${var.env}"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda.zip"
}

output "invoke_arn" {
  value = aws_lambda_function.api.invoke_arn
}

output "function_name" {
  value = aws_lambda_function.api.function_name
}
