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

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "tf-vpc-gel"
  cidr = "10.3.0.0/16"

  azs             = ["${var.aws_region}a"]
  private_subnets = ["10.3.0.0/24"]
  public_subnets  = ["10.3.100.0/24"]

  enable_nat_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "gel"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  count           = 1
  route_table_id  = module.vpc.vpc_main_route_table_id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_iam_policy" "lambda_networking" {
  name = "tf_networking"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Effect   = "Allow"
        Resource = ["*"]
      },
    ]
  })
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
    aws_iam_policy.lambda_networking.arn,
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
        Resource = ["${aws_s3_bucket.bucket_a.arn}/*"]
      },
      {
        Action = [
          "s3:PutObject",
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.bucket_b.arn}/*"]
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
  handler       = "app.handler"
  runtime       = "python3.8"
  environment {
    variables = {
      CLOUDWATCH_LOGS_ENABLE = true
      foo                    = true
    }
  }
  vpc_config {
    subnet_ids = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

}

resource "aws_security_group" "lambda" {
  name        = "tf_lambda"
  description = "egress only"
  vpc_id      = module.vpc.vpc_id



  egress { 
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Terraform   = "true"
    Environment = "gel"
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