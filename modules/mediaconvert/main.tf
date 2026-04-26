# IAM role that MediaConvert assumes when running transcoding jobs
# MediaConvert needs this role to read from the input bucket and write to the output bucket
resource "aws_iam_role" "mediaconvert" {
  name = "mediaconvert-role-${var.env}"

  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "mediaconvert.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Grants MediaConvert read access to the input bucket and write access to the output bucket
# Without this, MediaConvert jobs would fail with an access denied error on S3
resource "aws_iam_role_policy" "s3" {
  name = "mediaconvert-s3-${var.env}"
  role = aws_iam_role.mediaconvert.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [var.input_bucket_arn, "${var.input_bucket_arn}/*"]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject"],
        Resource = [var.output_bucket_arn, "${var.output_bucket_arn}/*"]
      }
    ]
  })
}

# IAM role for the trigger Lambda — separate from the main API Lambda role
resource "aws_iam_role" "trigger_lambda_role" {
  name = "mediaconvert-trigger-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Grants the trigger Lambda permission to:
# - Create MediaConvert jobs
# - Pass the MediaConvert IAM role to the job (iam:PassRole is required when passing a role to another service)
# - Write logs to CloudWatch for debugging
resource "aws_iam_role_policy" "trigger_lambda_policy" {
  name = "mediaconvert-trigger-policy-${var.env}"
  role = aws_iam_role.trigger_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["mediaconvert:CreateJob"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["iam:PassRole"],
        Resource = aws_iam_role.mediaconvert.arn
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

# Packages the trigger Lambda code into a zip at plan/apply time
# Source lives in trigger/index.js — built separately from the API Lambda
data "archive_file" "trigger" {
  type        = "zip"
  output_path = "${path.module}/trigger.zip"
  source_dir  = "${path.module}/trigger"
}

# The trigger Lambda — invoked automatically by S3 when a file is uploaded to the input bucket
# Starts a MediaConvert job to transcode the video to HLS format for streaming
resource "aws_lambda_function" "trigger" {
  function_name = "mediaconvert-trigger-${var.env}"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.trigger_lambda_role.arn
  filename      = data.archive_file.trigger.output_path

  environment {
    variables = {
      MC_ROLE_ARN   = aws_iam_role.mediaconvert.arn
      MC_ENDPOINT   = "https://mediaconvert.${var.region}.amazonaws.com"
      OUTPUT_BUCKET = var.output_bucket_id
    }
  }
}

# Grants S3 permission to invoke the trigger Lambda
# source_arn scopes it to only the input bucket — other buckets cannot trigger this Lambda
resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.input_bucket_arn
}

# Configures the input bucket to fire an event whenever a file is uploaded
# This is what automatically kicks off the MediaConvert transcoding pipeline
resource "aws_s3_bucket_notification" "trigger" {
  bucket = var.input_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger.arn
    events              = ["s3:ObjectCreated:*"]
  }

  # Lambda permission must exist before the notification is created
  # otherwise S3 cannot validate it has permission to invoke the function
  depends_on = [aws_lambda_permission.s3]
}
