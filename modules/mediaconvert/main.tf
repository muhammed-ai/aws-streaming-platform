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
# - Write to DynamoDB so the video appears in the catalog immediately as "processing"
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
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"],
        Resource = var.dynamodb_table_arn
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
  function_name    = "mediaconvert-trigger-${var.env}"
  runtime          = "nodejs18.x"
  handler          = "index.handler"
  role             = aws_iam_role.trigger_lambda_role.arn
  filename         = data.archive_file.trigger.output_path
  source_code_hash = data.archive_file.trigger.output_base64sha256

  environment {
    variables = {
      MC_ROLE_ARN    = aws_iam_role.mediaconvert.arn
      MC_ENDPOINT    = "https://mediaconvert.${var.region}.amazonaws.com"
      OUTPUT_BUCKET  = var.output_bucket_id
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }
}

# Grants S3 permission to invoke the trigger Lambda
# source_arn scopes it to only the input bucket — other buckets cannot trigger this Lambda
resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke-v2"
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

# ── ON-COMPLETE LAMBDA ──────────────────────────────────────────────────────
# Triggered by EventBridge when a MediaConvert job finishes.
# Writes the video record to DynamoDB so it appears in the catalog automatically.

# IAM role for the on-complete Lambda
resource "aws_iam_role" "on_complete_role" {
  name = "mediaconvert-on-complete-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Grants the on-complete Lambda permission to write to DynamoDB and CloudWatch logs
resource "aws_iam_role_policy" "on_complete_policy" {
  name = "mediaconvert-on-complete-policy-${var.env}"
  role = aws_iam_role.on_complete_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"],
        Resource = var.dynamodb_table_arn
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

# Package the on-complete Lambda code
data "archive_file" "on_complete" {
  type        = "zip"
  output_path = "${path.module}/on_complete.zip"
  source_dir  = "${path.module}/on_complete"
}

# The on-complete Lambda — writes video metadata to DynamoDB when MediaConvert finishes
resource "aws_lambda_function" "on_complete" {
  function_name    = "mediaconvert-on-complete-${var.env}"
  runtime          = "nodejs18.x"
  handler          = "index.handler"
  role             = aws_iam_role.on_complete_role.arn
  filename         = data.archive_file.on_complete.output_path
  source_code_hash = data.archive_file.on_complete.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }
}

# EventBridge rule — fires on any MediaConvert job state change (COMPLETE, ERROR, CANCELED)
resource "aws_cloudwatch_event_rule" "mediaconvert_complete" {
  name        = "mediaconvert-job-complete-${var.env}"
  description = "Fires when a MediaConvert job changes state"

  event_pattern = jsonencode({
    source      = ["aws.mediaconvert"],
    "detail-type" = ["MediaConvert Job State Change"]
  })
}

# Wires the EventBridge rule to the on-complete Lambda
resource "aws_cloudwatch_event_target" "on_complete" {
  rule      = aws_cloudwatch_event_rule.mediaconvert_complete.name
  target_id = "mediaconvert-on-complete"
  arn       = aws_lambda_function.on_complete.arn
}

# Grants EventBridge permission to invoke the on-complete Lambda
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.on_complete.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.mediaconvert_complete.arn
}
