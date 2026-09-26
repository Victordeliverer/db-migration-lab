# =============================================================================
# VPC
# =============================================================================
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true   # required for interface VPC endpoints' private DNS

  tags = { Name = "${var.name_prefix}-vpc" }
}

# =============================================================================
# Private subnets — two AZs, no public subnets, no NAT Gateway, no Internet
# Gateway. Everything reaches AWS services through VPC endpoints instead.
# This is why there's no route to 0.0.0.0/0 anywhere in this module.
# =============================================================================
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-private-${count.index == 0 ? "a" : "b"}"
  }
}

# =============================================================================
# Route table — local-only (no 0.0.0.0/0 route). The S3 gateway endpoint
# below adds its own prefix-list route automatically.
# =============================================================================
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# DMS replication subnet group — DMS needs its own subnet group resource
# type, distinct from an RDS/Aurora db_subnet_group.
# =============================================================================
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.name_prefix}-dms-subnet-group"
  replication_subnet_group_description = "Private subnets for the DMS replication instance"
  subnet_ids                           = aws_subnet.private[*].id

  tags = { Name = "${var.name_prefix}-dms-subnet-group" }
}

# =============================================================================
# Aurora DB subnet group (used by the aurora module on Day 3, defined here
# since it depends only on networking).
# =============================================================================
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.name_prefix}-aurora-subnet-group" }
}

# =============================================================================
# Security group for VPC interface endpoints. Allows HTTPS from inside the
# VPC only — this is what lets EC2/DMS reach Secrets Manager, SSM, etc.
# without any path to the public internet.
# =============================================================================
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-vpce-sg" }
}

# =============================================================================
# Interface VPC endpoints: Secrets Manager, SSM, EC2 Messages, SSM Messages.
# SSM + EC2 Messages + SSM Messages together are what make Session Manager
# work with zero public IP and zero SSH key on the source EC2 instance.
# =============================================================================
locals {
  interface_endpoints = [
    "secretsmanager",
    "ssm",
    "ec2messages",
    "ssmmessages",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_endpoints)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.eu-west-1.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-${each.value}" }
}

# =============================================================================
# Gateway endpoint: S3. Free, and avoids routing S3 traffic (validation
# exports, state bootstrap) through a NAT Gateway you don't have anyway.
# =============================================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name_prefix}-vpce-s3" }
}

# =============================================================================
# VPC Flow Logs — optional, off by default to save cost (CloudWatch Logs
# ingestion is billed). Turn on for Day 6 observability work if budget allows.
# =============================================================================
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = { Name = "${var.name_prefix}-flow-logs" }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.name_prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.name_prefix}-flow-logs-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count                = var.enable_flow_logs ? 1 : 0
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn          = aws_iam_role.flow_logs[0].arn

  tags = { Name = "${var.name_prefix}-flow-log" }
}
