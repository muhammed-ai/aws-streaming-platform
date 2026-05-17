# IAM role that Lambda assumes at runtime — required for any Lambda function to execute
resource "aws_iam_role" "lambda_role" {
  name = "netflix-lambda-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attaches AWS managed policy for basic Lambda execution — allows writing logs to CloudWatch
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allows Lambda to read and write video metadata in DynamoDB
# Scoped to only the videos table — not all DynamoDB tables in the account
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

# Allows Lambda to read uploaded videos from the input S3 bucket
# Needed to access video files when generating signed CloudFront URLs
resource "aws_iam_role_policy" "s3" {
  name = "lambda-s3-${var.env}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject", "s3:ListBucket"],
      Resource = [var.s3_input_bucket_arn, "${var.s3_input_bucket_arn}/*",
                  var.s3_output_bucket_arn, "${var.s3_output_bucket_arn}/*"]
    }]
  })
}

# The main API Lambda function — handles all requests from API Gateway
# Runs the backend/index.js handler which generates signed CloudFront URLs for video playback
resource "aws_lambda_function" "api" {
  function_name = "netflix-api-${var.env}"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda.zip"

  # Only set source_code_hash if the zip exists — avoids plan-time error in CI before build step
  source_code_hash = fileexists("${path.module}/lambda.zip") ? filebase64sha256("${path.module}/lambda.zip") : null

  environment {
    variables = {
      # DynamoDB table name — matches the table created by the dynamodb module
      DYNAMODB_TABLE = "videos-${var.env}"

      # CloudFront domain for building signed streaming URLs — set after first deploy
      # Format: https://xxxx.cloudfront.net  (no trailing slash)
      CF_URL = var.cloudfront_domain

      # CloudFront key pair ID and private key for signed URL generation
      # Create a key pair in AWS Console → CloudFront → Key management → Key pairs
      # Store the private key in SSM Parameter Store and reference it here
      KEY_PAIR_ID    = var.cf_key_pair_id
      PRIVATE_KEY    = var.cf_private_key
      OUTPUT_BUCKET  = "netflix-${var.env}-output"
    }
  }
}

# Exposes the Lambda invoke ARN — used by API Gateway to wire up the integration
output "invoke_arn" {
  value = aws_lambda_function.api.invoke_arn
}

# Exposes the function name — used by API Gateway to grant invoke permission
output "function_name" {
  value = aws_lambda_function.api.function_name
}

# Exposes the Lambda IAM role ARN — used by S3 bucket policy to allow manifest reads
output "role_arn" {
  value = aws_iam_role.lambda_role.arn
}
