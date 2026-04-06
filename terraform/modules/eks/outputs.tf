output "cluster_id" {
  # description = "ID của EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  # description = "Tên của EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  # description = "ARN của EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  # description = "Endpoint URL của EKS API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  # description = "Certificate Authority data của EKS cluster (base64 encoded)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  # description = "Phiên bản Kubernetes của EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_iam_role_arn" {
  # description = "ARN của IAM Role cho EKS control plane"
  value       = aws_iam_role.eks_cluster.arn
}

output "node_group_iam_role_arn" {
  # description = "ARN của IAM Role cho EKS node group"
  value       = aws_iam_role.eks_node_group.arn
}

output "node_group_name" {
  # description = "Tên của EKS node group"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_group_status" {
  # description = "Trạng thái của EKS node group"
  value       = aws_eks_node_group.main.status
}

output "oidc_provider_arn" {
  # description = "ARN của OIDC Identity Provider (dùng cho IRSA)"
  value       = aws_iam_openid_connect_provider.eks_oidc.arn
}

output "oidc_provider_url" {
  # description = "URL của OIDC Identity Provider"
  value       = aws_iam_openid_connect_provider.eks_oidc.url
}

output "cloudwatch_log_group_name" {
  # description = "Tên CloudWatch log group của EKS cluster"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}
