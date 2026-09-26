module "network" {
  source = "../../modules/network"

  vpc_cidr    = "10.20.0.0/16"
  name_prefix = "db-migration-lab"

  # Off by default to save cost. Flip to true for Day 6 observability work.
  enable_flow_logs = false
}
