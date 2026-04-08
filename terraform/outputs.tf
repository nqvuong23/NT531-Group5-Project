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

output "eks_node_group_name" {
  description = "EKS node group name"
  value       = module.eks.node_group_name
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
