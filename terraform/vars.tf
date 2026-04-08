# ============================================================
# ROOT: vars.tf
# Khai báo toàn bộ biến. Giá trị được gán trong terraform.tfvars
# ============================================================

# ------- General -------
variable "aws_region" {
  # description = "AWS region để triển khai hạ tầng (vd: ap-southeast-1)"
  type = string
}

variable "aws_profile" {
  type = string
}

variable "project_name" {
  # description = "Tên project ngắn gọn, dùng làm prefix (vd: myproject)"
  type = string
}

variable "environment" {
  # description = "Môi trường triển khai (dev / staging / prod)"
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment phải là một trong: dev, staging, prod"
  }
}

# S3 bucket name
variable "s3_bucket_name" {
  type = string
}

# ------- VPC & Networking -------
variable "vpc_cidr" {
  # description = "CIDR block của VPC"
  type = string
}

variable "public_subnet_cidrs" {
  # description = "Danh sách CIDR cho các public subnet (cần ít nhất 2 cho HA)"
  type = list(string)
}

variable "private_subnet_cidrs" {
  # description = "Danh sách CIDR cho các private subnet (cần ít nhất 2 cho EKS)"
  type = list(string)
}

variable "availability_zones" {
  # description = "Danh sách AZ để deploy (số lượng phải khớp với số subnet)"
  type = list(string)
}

variable "ssh_allowed_cidrs" {
  # description = "Danh sách CIDR được phép SSH vào EC2 instances (giới hạn IP văn phòng/VPN)"
  type = list(string)
}

variable "grafana_allowed_cidrs" {
  # description = "Danh sách CIDR được phép truy cập Grafana UI (port 3000)"
  type = list(string)
}

# ------- EKS Cluster -------
variable "eks_cluster_version" {
  # description = "Phiên bản Kubernetes cho EKS (vd: 1.29)"
  type = string
}

variable "eks_endpoint_private_access" {
  # description = "Bật private endpoint cho EKS API server"
  type    = bool
  default = true
}

variable "eks_endpoint_public_access" {
  # description = "Bật public endpoint cho EKS API server"
  type    = bool
  default = true
}

variable "eks_public_access_cidrs" {
  # description = "CIDR được phép truy cập EKS public API endpoint"
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "eks_enabled_cluster_log_types" {
  # description = "Các log type EKS gửi lên CloudWatch"
  type    = list(string)
  default = ["api", "audit", "authenticator"]
}

variable "eks_log_retention_days" {
  # description = "Số ngày giữ EKS logs trong CloudWatch"
  type    = number
  default = 7
}

# ------- EKS Node Group -------
variable "eks_node_instance_type" {
  # description = "Instance type cho EKS worker nodes"
  type = string
}

variable "eks_node_ami_type" {
  # description = "Loại AMI cho EKS nodes (AL2_x86_64, AL2_ARM_64, BOTTLEROCKET_x86_64...)"
  type    = string
  default = "AL2_x86_64"
}

variable "eks_node_disk_size" {
  # description = "Dung lượng EBS root volume (GB) cho mỗi EKS node"
  type    = number
  default = 50
}

variable "eks_node_capacity_type" {
  # description = "Loại capacity cho EKS nodes: ON_DEMAND hoặc SPOT"
  type    = string
  default = "ON_DEMAND"
}

variable "eks_node_desired_size" {
  # description = "Số node mong muốn trong EKS node group"
  type = number
}

variable "eks_node_min_size" {
  # description = "Số node tối thiểu trong EKS node group"
  type = number
}

variable "eks_node_max_size" {
  # description = "Số node tối đa trong EKS node group"
  type = number
}

variable "eks_node_max_unavailable" {
  # description = "Số node tối đa unavailable khi rolling update"
  type    = number
  default = 1
}

variable "eks_node_labels" {
  # description = "Kubernetes labels gắn vào tất cả EKS nodes"
  type    = map(string)
  default = {}
}

# ------- EC2 Instances (K6 & Observation) -------
variable "ec2_ami_id" {
  # description = "AMI ID cố định cho EC2 (để trống '' để tự động tìm theo filter)"
  type    = string
  default = ""
}

variable "ec2_ami_owner" {
  # description = "Owner ID của AMI khi tự động tìm (amazon=137112412989, ubuntu=099720109477)"
  type = string
}

variable "ec2_ami_name_filter" {
  # description = "Pattern tên AMI để tự động tìm (vd: amzn2-ami-hvm-*-x86_64-gp2)"
  type = string
}

variable "key_pair_name" {
  # description = "Tên EC2 Key Pair để SSH (để trống để dùng SSM Session Manager thay thế)"
  type    = string
  default = ""
}

variable "key_pair_path" {
  type    = string
  default = ""
}

variable "ec2_enable_detailed_monitoring" {
  # description = "Bật CloudWatch detailed monitoring cho EC2 (1-phút interval)"
  type    = bool
  default = false
}

# K6 instance
variable "k6_instance_type" {
  # description = "Instance type cho K6 load testing instance"
  type = string
}

variable "k6_volume_type" {
  # description = "Loại EBS volume cho K6 instance"
  type    = string
  default = "gp3"
}

variable "k6_volume_size" {
  # description = "Dung lượng ổ đĩa (GB) cho K6 instance"
  type    = number
  default = 30
}

variable "k6_public_ip" {
  # description = "Gán Elastic IP public cho K6 instance"
  type    = bool
  default = false
}

variable "k6_version" {
  # description = "Phiên bản K6 cần cài đặt"
  type = string
}

# Observation instance
variable "observation_instance_type" {
  # description = "Instance type cho Observation instance"
  type = string
}

variable "observation_volume_type" {
  # description = "Loại EBS volume cho Observation instance"
  type    = string
  default = "gp3"
}

variable "observation_volume_size" {
  # description = "Dung lượng ổ đĩa (GB) cho Observation instance"
  type    = number
  default = 50
}

variable "observation_public_ip" {
  # description = "Gán Elastic IP public cho Observation instance (cần để truy cập Grafana)"
  type    = bool
  default = true
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  # description = "Mật khẩu Grafana admin (nên dùng AWS Secrets Manager trong production)"
  type      = string
  sensitive = true
}
