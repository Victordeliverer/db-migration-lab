output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "dms_subnet_group_name" {
  value = aws_dms_replication_subnet_group.this.id
}

output "aurora_subnet_group_name" {
  value = aws_db_subnet_group.aurora.name
}

output "vpc_endpoints_sg_id" {
  description = "Reuse this SG ID as a reference source when writing source-db/aurora/dms security groups."
  value       = aws_security_group.vpc_endpoints.id
}
