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

data "archive_file" "trigger" {
  type        = "zip"
  output_path = "${path.module}/trigger.zip"

  source {
    content  = <<-EOF
      const AWS = require('aws-sdk');
      const mc = new AWS.MediaConvert({ endpoint: process.env.MC_ENDPOINT });
      exports.handler = async (event) => {
        const key = event.Records[0].s3.object.key;
        const bucket = event.Records[0].s3.bucket.name;
        await mc.createJob({
          Role: process.env.MC_ROLE_ARN,
          Settings: {
            Inputs: [{ FileInput: 's3://' + bucket + '/' + key }],
            OutputGroups: [{
              OutputGroupSettings: {
                Type: 'HLS_GROUP_SETTINGS',
                HlsGroupSettings: { Destination: 's3://${var.output_bucket_id}/' + key.split('.')[0] + '/' }
              },
              Outputs: [{ Preset: 'System-Avc_16x9_1080p_29_97fps_8500kbps_qvbr' }]
            }]
          }
        }).promise();
      };
    EOF
    filename = "index.js"
  }
}

resource "aws_lambda_function" "trigger" {
  function_name = "mediaconvert-trigger-${var.env}"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.trigger_lambda_role.arn
  filename      = data.archive_file.trigger.output_path

  environment {
    variables = {
      MC_ROLE_ARN  = aws_iam_role.mediaconvert.arn
      MC_ENDPOINT  = "https://mediaconvert.${var.region}.amazonaws.com"
    }
  }
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.input_bucket_arn
}

resource "aws_s3_bucket_notification" "trigger" {
  bucket = var.input_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3]
}