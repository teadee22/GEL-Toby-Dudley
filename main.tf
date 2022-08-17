#------------------------------------------------------------------------------
# Terraform Config
#------------------------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  profile = "default"
  region  = var.aws_region
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "image_processor_lambda" {
  name               = "tf_gel_iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  managed_policy_arns = [
    aws_iam_policy.lambda_s3_buckets.arn,
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

resource "aws_iam_policy" "lambda_s3_buckets" {
  name = "tf_gel_lambda_s3_bucket_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.bucket_a.arn]
      },
      {
        Action = [
          "s3:PutObject",
        ]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.bucket_b.arn]
      },
    ]
  })
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bucket_a.arn
}

resource "aws_lambda_function" "image_processor" {
  filename      = "app/app.zip"
  function_name = "image_processor_strip_exif"
  role          = aws_iam_role.image_processor_lambda.arn
  handler       = "exports.handler"
  runtime       = "python3.8"
  environment {
    variables = {
      CLOUDWATCH_LOGS_ENABLE = true
    }
  }
}

resource "aws_s3_bucket" "bucket_a" {
  bucket = "gel-bucket-a"
}

resource "aws_s3_bucket" "bucket_b" {
  bucket = "gel-bucket-b"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket_a.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}



resource "aws_iam_policy" "logs" {
  name = "tf_gel_image_processor_lambda_logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = ["${aws_cloudwatch_log_group.main.arn}"]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${aws_lambda_function.image_processor.function_name}"
  retention_in_days = 1
}