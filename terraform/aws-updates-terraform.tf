terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    
# AWS Secrets Manager - SMTPパスワード用
resource "aws_secretsmanager_secret" "smtp_password" {
  name = "aws-updates-smtp-password"
  description = "SMTP password for AWS Updates notification system"
}

resource "aws_secretsmanager_secret_version" "smtp_password" {
  secret_id     = aws_secretsmanager_secret.smtp_password.id
  secret_string = jsonencode({
    password = "your_smtp_password"  # 実際のデプロイ前に変更してください
  })
}

# IAM Policy - Secrets Manager アクセス用
resource "aws_iam_policy" "lambda_secrets_policy" {
  name        = "aws_updates_secrets_access"
  description = "Allow Lambda to access SMTP password in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.smtp_password.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_secrets_policy.arn
}

# CloudWatch Event Rule - 定期実行用 (毎日午前9時に実行)
resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "daily-aws-updates-check"
  description         = "Trigger AWS updates check daily"
  schedule_expression = "cron(0 9 * * ? *)"  # UTC時間で毎日午前9時 (日本時間で午後6時)
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_trigger.name
  target_id = "TriggerLambda"
  arn       = aws_lambda_function.aws_updates_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aws_updates_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_trigger.arn
}

# 出力
output "lambda_function_name" {
  value = aws_lambda_function.aws_updates_lambda.function_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.updates_bucket.id
}

output "cloudwatch_rule_name" {
  value = aws_cloudwatch_event_rule.daily_trigger.name
}
}
  }
}

provider "aws" {
  region = "ap-northeast-1"  # 東京リージョン（適宜変更してください）
}

# S3バケット - 更新情報保存用
resource "aws_s3_bucket" "updates_bucket" {
  bucket = "your-aws-updates-bucket"  # ユニークな名前に変更してください
}

resource "aws_s3_bucket_ownership_controls" "updates_bucket_ownership" {
  bucket = aws_s3_bucket.updates_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "updates_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.updates_bucket_ownership]
  bucket     = aws_s3_bucket.updates_bucket.id
  acl        = "private"
}

# IAM Role - Lambda実行用
resource "aws_iam_role" "lambda_exec_role" {
  name = "aws_updates_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy - S3アクセス用
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "aws_updates_s3_access"
  description = "Allow Lambda to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.updates_bucket.arn,
          "${aws_s3_bucket.updates_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM Policy - CloudWatch Logs用
resource "aws_iam_policy" "lambda_logs_policy" {
  name        = "aws_updates_logs_access"
  description = "Allow Lambda to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM Policy - Bedrock API用
resource "aws_iam_policy" "lambda_bedrock_policy" {
  name        = "aws_updates_bedrock_access"
  description = "Allow Lambda to use Amazon Bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:InvokeModel"
        ]
        Effect   = "Allow"
        Resource = "*"  # 必要に応じて特定のモデルARNに制限することを検討
      }
    ]
  })
}

# IAMポリシーのアタッチ
resource "aws_iam_role_policy_attachment" "lambda_s3_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_logs_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_logs_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_bedrock_policy.arn
}

# Lambda関数
resource "aws_lambda_function" "aws_updates_lambda" {
  filename      = "lambda_function.zip"  # Lambda関数コードのZIPファイル
  function_name = "aws_updates_emailer"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 256

  environment {
    variables = {
      BUCKET_NAME    = aws_s3_bucket.updates_bucket.id
      LAST_UPDATE_KEY = "last_update.json"
      SENDER_EMAIL   = "your-sender-email@example.com"
      RECEIVER_EMAIL = "your-email@example.com"
      SMTP_SERVER    = "smtp.example.com"
      SMTP_PORT      = "587"
      SMTP_USERNAME  = "your_smtp_username"
      # 注意: パスワードは環境変数に直接書くのではなく、AWS Systems Manager Parameter StoreやSecrets Managerを使用することを推奨
      # SMTP_PASSWORD = "your_smtp_password"
    }
  }
}