output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "dms_subnet_group_name" {
  value = module.network.dms_subnet_group_name
}

output "aurora_subnet_group_name" {
  value = module.network.aurora_subnet_group_name
}

output "vpc_endpoints_sg_id" {
  value = module.network.vpc_endpoints_sg_id
}

