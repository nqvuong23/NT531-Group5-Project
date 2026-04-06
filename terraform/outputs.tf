# ============================================================
# ROOT: outputs.tf
# Xuất các giá trị quan trọng sau khi apply
# ============================================================

# ------- VPC -------
output "vpc_id" {
  description = "ID of VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "ID list of public subnet"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "ID list of private subnet"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ip" {
  description = "Public IP of NAT Gateway (outbound traffic from private subnet)"
  value       = module.vpc.nat_gateway_public_ip
}

# ------- EKS -------
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API endpoint of EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of EKS cluster"
  value       = module.eks.cluster_version
}

output "eks_oidc_provider_arn" {
  description = "ARN OIDC Provider (used for IAM Roles for Service Accounts)"
  value       = module.eks.oidc_provider_arn
}

output "eks_node_group_name" {
  description = "EKS node group name"
  value       = module.eks.node_group_name
}

output "eks_kubeconfig_command" {
  description = "Update command kubeconfig for connection to EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ------- EC2: K6 -------
output "k6_instance_id" {
  description = "ID of K6 instance"
  value       = module.ec2.k6_instance_id
}

output "k6_private_ip" {
  description = "Private IP of K6 instance"
  value       = module.ec2.k6_private_ip
}

output "k6_public_ip" {
  description = "Public IP of K6 instance (if it's available)"
  value       = module.ec2.k6_public_ip
}

output "k6_ssh_command" {
  description = "SSH command vào K6 instance"
  value = var.key_pair_name != "" ? (
    module.ec2.k6_public_ip != null ?
    "ssh -i ${var.key_pair_name}.pem ec2-user@${module.ec2.k6_public_ip}" :
    "ssh -i ${var.key_pair_name}.pem ec2-user@${module.ec2.k6_private_ip}"
  ) : "aws ssm start-session --target ${module.ec2.k6_instance_id} --region ${var.aws_region}"
}

# ------- EC2: Observation -------
output "observation_instance_id" {
  description = "ID of Observation instance"
  value       = module.ec2.observation_instance_id
}

output "observation_private_ip" {
  description = "Private IP of Observation instance"
  value       = module.ec2.observation_private_ip
}

output "observation_public_ip" {
  description = "Public IP of Observation instance (Elastic IP)"
  value       = module.ec2.observation_public_ip
}

output "grafana_url" {
  description = "URL to access Grafana dashboard"
  value       = module.ec2.grafana_url
}

output "victoriametrics_url" {
  description = "URL to access VictoriaMetrics (internal)"
  value       = module.ec2.victoriametrics_url
}

output "otel_collector_grpc_endpoint" {
  description = "gRPC endpoint of OTel Collector"
  value       = module.ec2.otel_collector_grpc_endpoint
}

output "otel_collector_http_endpoint" {
  description = "HTTP endpoint of OTel Collector"
  value       = module.ec2.otel_collector_http_endpoint
}

# ------- Summary -------
output "infrastructure_summary" {
  description = "Summary of all infrastructure deployed"
  value = {
    project     = var.project_name
    environment = var.environment
    region      = var.aws_region
    vpc_id      = module.vpc.vpc_id
    eks = {
      cluster_name = module.eks.cluster_name
      version      = module.eks.cluster_version
      node_group   = module.eks.node_group_name
    }
    ec2 = {
      k6_ip          = module.ec2.k6_private_ip
      observation_ip = coalesce(module.ec2.observation_public_ip, module.ec2.observation_private_ip)
      grafana_url    = module.ec2.grafana_url
    }
  }
}
