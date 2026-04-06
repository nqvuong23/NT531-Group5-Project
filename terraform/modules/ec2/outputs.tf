output "k6_instance_id" {
  # description = "ID của K6 EC2 instance"
  value       = aws_instance.k6.id
}

output "k6_private_ip" {
  # description = "Private IP của K6 instance"
  value       = aws_instance.k6.private_ip
}

output "k6_public_ip" {
  # description = "Public IP của K6 instance (nếu có Elastic IP)"
  value       = length(aws_eip.k6) > 0 ? aws_eip.k6[0].public_ip : null
}

output "k6_public_dns" {
  # description = "Public DNS của K6 instance"
  value       = aws_instance.k6.public_dns
}

output "observation_instance_id" {
  # description = "ID của Observation EC2 instance"
  value       = aws_instance.observation.id
}

output "observation_private_ip" {
  # description = "Private IP của Observation instance"
  value       = aws_instance.observation.private_ip
}

output "observation_public_ip" {
  # description = "Public IP của Observation instance (Elastic IP)"
  value       = length(aws_eip.observation) > 0 ? aws_eip.observation[0].public_ip : null
}

output "grafana_url" {
  # description = "URL truy cập Grafana dashboard"
  value = length(aws_eip.observation) > 0 ? (
    "http://${aws_eip.observation[0].public_ip}:3000"
  ) : "http://${aws_instance.observation.private_ip}:3000"
}

output "victoriametrics_url" {
  # description = "URL truy cập VictoriaMetrics (internal)"
  value       = "http://${aws_instance.observation.private_ip}:8428"
}

output "otel_collector_grpc_endpoint" {
  # description = "gRPC endpoint của OTel Collector (internal)"
  value       = "${aws_instance.observation.private_ip}:4317"
}

output "otel_collector_http_endpoint" {
  # description = "HTTP endpoint của OTel Collector (internal)"
  value       = "http://${aws_instance.observation.private_ip}:4318"
}

output "ec2_iam_role_arn" {
  # description = "ARN của IAM Role gắn vào EC2 instances"
  value       = aws_iam_role.ec2_instance_role.arn
}

output "ec2_instance_profile_name" {
  # description = "Tên của EC2 Instance Profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}
