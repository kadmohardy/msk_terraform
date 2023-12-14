# Get the AccountId
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_iam_policy_document" "pipe_assume_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pipe_iam_policy_document" {
  statement {
    sid    = "AllowPipeToAccessSQS"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:SendMessage"
    ]
    resources = [aws_sqs_queue.accounts_request_sqs.arn]
  }

  statement {
    sid    = "AllowPipeToAccessKafka"
    effect = "Allow"
    actions = [
      "kafka:DescribeCluster",
      "kafka:DescribeClusterV2",
      "kafka:GetBootstrapBrokers"
    ]
    resources = [aws_msk_cluster.kafka.arn]
  }

  statement {
    sid    = "AllowPipeToAccessEC2AndLogs"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid = "InvokeEnrichmentLambdaFunction"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = ["*"]
  }
}

# Data to create policies for lambda
data "aws_iam_policy_document" "lambda_assume_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# data "archive_file" "enrichment_customer_request_lambda_file" {
#   type        = "zip"
#   source_file = "${path.module}/lambda/enrich-customer-request/index.mjs"
#   output_path = "${path.module}/lambda/enrich-customer-request/index.zip"
# }

# data "archive_file" "process_customer_request_lambda_file" {
#   type        = "zip"
#   source_file = "${path.module}/lambda/process-customer-request/index.mjs"
#   output_path = "${path.module}/lambda/process-customer-request/index.zip"
# }
