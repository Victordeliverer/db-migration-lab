resource "aws_rds_cluster" "aurora" {
  cluster_identifier     = "migration-lab-aurora"
  engine                 = "aurora-postgresql"
  engine_version         = "15.19"          # pinned — matches the CLI check
  database_name          = "appdb"
  master_username        = "postgres"
  master_password        = null              # use manage_master_user_password instead
  manage_master_user_password = true         # Secrets Manager-generated password
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  storage_encrypted      = true
  kms_key_id              = aws_kms_key.aurora.arn
  deletion_protection    = true
  backup_retention_period = 7
  preferred_backup_window = "02:00-03:00"
  skip_final_snapshot    = false
  final_snapshot_identifier = "migration-lab-aurora-final"

  tags = local.common_tags
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "migration-lab-aurora-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version  # inherits the pin
  auto_minor_version_upgrade = false   # don't let AWS silently bump it

  tags = local.common_tags
}