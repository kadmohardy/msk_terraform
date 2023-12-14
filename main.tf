################################################################################
# Kafka Cluster
################################################################################
resource "aws_kms_key" "kafka_kms_key" {
  description = "Key for Apache Kafka"
}

resource "aws_cloudwatch_log_group" "kafka_log_group" {
  name = "kafka_broker_logs"
}

resource "aws_msk_configuration" "kafka_config" {
  kafka_versions    = ["3.4.0"]
  name              = "${var.global_prefix}-config"
  server_properties = <<EOF
auto.create.topics.enable = true
delete.topic.enable = true
EOF
}

resource "aws_msk_cluster" "kafka" {
  cluster_name           = var.global_prefix
  kafka_version          = "3.4.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type = "kafka.t3.small" # default value
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    client_subnets = [aws_subnet.private_subnet[0].id,
      aws_subnet.private_subnet[1].id,
    aws_subnet.private_subnet[2].id]
    security_groups = [aws_security_group.kafka.id]
  }
  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
    }
    encryption_at_rest_kms_key_arn = aws_kms_key.kafka_kms_key.arn
  }
  configuration_info {
    arn      = aws_msk_configuration.kafka_config.arn
    revision = aws_msk_configuration.kafka_config.latest_revision
  }
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka_log_group.name
      }
    }
  }
}

################################################################################
# General
################################################################################

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_eip" "default" {
  depends_on = [aws_internet_gateway.default]
  domain     = "vpc"
}

resource "aws_route" "default" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

################################################################################
# Subnets
################################################################################

resource "aws_subnet" "private_subnet" {
  count                   = length(var.private_cidr_blocks)
  vpc_id                  = aws_vpc.default.id
  cidr_block              = element(var.private_cidr_blocks, count.index)
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "bastion_host_subnet" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = var.cidr_blocks_bastion_host[0]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
}

################################################################################
# Security groups
################################################################################

resource "aws_security_group" "kafka" {
  name   = "${var.global_prefix}-kafka"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port   = 0
    to_port     = 9092
    protocol    = "TCP"
    cidr_blocks = var.private_cidr_blocks
  }
  ingress {
    from_port   = 0
    to_port     = 9092
    protocol    = "TCP"
    cidr_blocks = var.cidr_blocks_bastion_host
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion_host" {
  name   = "${var.global_prefix}-bastion-host"
  vpc_id = aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "private_key" {
  key_name   = var.global_prefix
  public_key = tls_private_key.private_key.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.private_key.private_key_pem
  filename = "cert.pem"
}

resource "null_resource" "private_key_permissions" {
  depends_on = [local_file.private_key]
  provisioner "local-exec" {
    command     = "chmod 600 cert.pem"
    interpreter = ["bash", "-c"]
    on_failure  = continue
  }
}

################################################################################
# SQS queue
################################################################################
resource "aws_sqs_queue" "accounts_request_sqs" {
  name = "accounts-request"
}

################################################################################
# Bridge Pipes for MSK source
################################################################################
resource "awscc_pipes_pipe" "msk_pipe" {
  name     = "pipe-account-request"
  role_arn = aws_iam_role.pipe_iam_role.arn

  source = aws_msk_cluster.kafka.arn

  source_parameters = {

    managed_streaming_kafka_parameters = {
      topic_name        = var.topic_name,
      consumer_group_id = "group_1"
    }
  }

  target = aws_sqs_queue.accounts_request_sqs.arn
}


################################################################################
# Bridge Pipes for SQS source
################################################################################


# resource "awscc_pipes_pipe" "sqs_pipe" {
#   name     = "pipe-customer-request"
#   role_arn = aws_iam_role.pipe_iam_role.arn

#   source = aws_sqs_queue.customer_request_sqs.arn

#   source_parameters = {
#     sqs = {
#       sqs_queue_parameters = {
#         batch_size = 10
#       }
#     }

#     filter_criteria = {
#       filters = [{ pattern = "{ \"body\": { \"customer_type\": [\"Platinum\"] }}" }]
#     }
#   }

#   enrichment = module.enrich_customer_request_lambda.lambda_function_arn
#   enrichment_parameters = {
#     input_template = "{\"id\": \"<$.body.id>\",  \"customer_type\": \"<$.body.customer_type>\", \"query\": \"<$.body.query>\",\"severity\": \"<$.body.severity>\", \"created_date\" : \"<$.body.createdDate>\"}"
#   }

#   target = module.process_customer_request_lambda.lambda_function_arn
# }

# module "enrich_customer_request_lambda" {
#   source = "terraform-aws-modules/lambda/aws"

#   function_name          = "enrich-customer-request"
#   source_path            = "${path.module}/lambda/enrich-customer-request"
#   handler                = "index.handler"
#   runtime                = "nodejs18.x"
#   local_existing_package = "${path.module}/lambda/enrich-customer-request/index.zip"
#   create_role            = false
#   lambda_role            = aws_iam_role.enrich_customer_request_lambda_iam_role.arn
# }

# module "process_customer_request_lambda" {
#   source = "terraform-aws-modules/lambda/aws"

#   function_name          = "process-customer-request"
#   source_path            = "${path.module}/lambda/process-customer-request"
#   handler                = "index.handler"
#   runtime                = "nodejs18.x"
#   local_existing_package = "${path.module}/lambda/process-customer-request/index.zip"
#   create_role            = false
#   lambda_role            = aws_iam_role.process_customer_request_lambda_iam_role.arn
# }


################################################################################
# Client Machine (EC2)
################################################################################

resource "aws_instance" "bastion_host" {
  depends_on             = [aws_msk_cluster.kafka]
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.private_key.key_name
  subnet_id              = aws_subnet.bastion_host_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  user_data = templatefile("bastion.tftpl", {
    bootstrap_server_1 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[0]
    bootstrap_server_2 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[1]
    bootstrap_server_3 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[2]
  })
  root_block_device {
    volume_type = "gp2"
    volume_size = 100
  }
}

# ssh ec2-user@34.229.114.101 -i cert.pem
