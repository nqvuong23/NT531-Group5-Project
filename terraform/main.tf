# ============================================================
# ROOT: main.tf
# Entry point chính - khai báo provider, backend và gọi modules
# ============================================================

# ------- Local Values -------
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = formatdate("YYYY-MM-DD", timestamp())
  }

  eks_cluster_name = "${var.project_name}-${var.environment}-eks"
}

# Tạo keypair
resource "aws_key_pair" "keypair" {
  key_name   = var.key_pair_name
  public_key = file(var.key_pair_path)

  lifecycle {
    ignore_changes = [
      tags_all, # Bỏ qua các tags được gán tự động từ provider hoặc AWS
    ]
  }
}

# ============================================================
# MODULE 1: S3 Backend (State Storage)
# Lưu ý: Apply module này TRƯỚC, xem hướng dẫn bootstrap ở trên
# ============================================================
# module "s3_backend" {
#   source = "./modules/s3_backend"

#   bucket_name          = var.state_bucket_name
#   dynamodb_table_name  = var.state_dynamodb_table
#   force_destroy        = var.state_bucket_force_destroy
#   state_retention_days = var.state_retention_days

#   tags = local.common_tags
# }

# ============================================================
# MODULE 2: VPC & Networking
# ============================================================
module "vpc" {
  source = "./modules/vpc"

  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  availability_zones    = var.availability_zones
  eks_cluster_name      = local.eks_cluster_name
  ssh_allowed_cidrs     = var.ssh_allowed_cidrs
  grafana_allowed_cidrs = var.grafana_allowed_cidrs

  tags = local.common_tags
}

# ============================================================
# MODULE 3: EKS Cluster
# ============================================================
module "eks" {
  source = "./modules/eks"

  project_name    = var.project_name
  cluster_name    = local.eks_cluster_name
  cluster_version = var.eks_cluster_version

  # Networking - lấy output từ module vpc
  subnet_ids                = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids           = module.vpc.private_subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_security_group_id
  nodes_security_group_id   = module.vpc.eks_nodes_security_group_id

  # Cluster access
  endpoint_private_access = var.eks_endpoint_private_access
  endpoint_public_access  = var.eks_endpoint_public_access
  public_access_cidrs     = var.eks_public_access_cidrs

  # Logging
  enabled_cluster_log_types = var.eks_enabled_cluster_log_types
  log_retention_days        = var.eks_log_retention_days

  # Node Group
  node_instance_type   = var.eks_node_instance_type
  node_ami_type        = var.eks_node_ami_type
  node_disk_size       = var.eks_node_disk_size
  node_capacity_type   = var.eks_node_capacity_type
  node_desired_size    = var.eks_node_desired_size
  node_min_size        = var.eks_node_min_size
  node_max_size        = var.eks_node_max_size
  node_max_unavailable = var.eks_node_max_unavailable
  node_key_pair_name   = aws_key_pair.keypair.key_name
  node_labels          = var.eks_node_labels

  tags = local.common_tags

  depends_on = [module.vpc]
}

# ============================================================
# MODULE 4: EC2 Instances (K6 & Observation)
# ============================================================
module "ec2" {
  source = "./modules/ec2"

  project_name = var.project_name
  aws_region   = var.aws_region

  s3_bucket_name = var.s3_bucket_name

  # AMI configuration
  ami_id          = var.ec2_ami_id
  ami_owner       = var.ec2_ami_owner
  ami_name_filter = var.ec2_ami_name_filter

  # K6 instance
  k6_instance_type     = var.k6_instance_type
  k6_subnet_id         = module.vpc.public_subnet_ids[0]
  k6_security_group_id = module.vpc.k6_security_group_id
  k6_volume_type       = var.k6_volume_type
  k6_volume_size       = var.k6_volume_size
  k6_public_ip         = var.k6_public_ip
  k6_version           = var.k6_version

  # Observation instance
  observation_instance_type     = var.observation_instance_type
  observation_subnet_id         = module.vpc.public_subnet_ids[1]
  observation_security_group_id = module.vpc.observation_security_group_id
  observation_volume_type       = var.observation_volume_type
  observation_volume_size       = var.observation_volume_size
  observation_public_ip         = var.observation_public_ip

  grafana_admin_user      = var.grafana_admin_user
  grafana_admin_password  = var.grafana_admin_password
  victoriametrics_version = var.victoriametrics_version
  otel_collector_version  = var.otel_collector_version

  # Common
  key_pair_name              = aws_key_pair.keypair.key_name
  enable_detailed_monitoring = var.ec2_enable_detailed_monitoring

  tags = local.common_tags

  depends_on = [module.vpc]
}
