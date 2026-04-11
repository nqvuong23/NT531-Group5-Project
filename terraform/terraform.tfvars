# ============================================================
# terraform.tfvars
# File DUY NHẤT để gán giá trị cho tất cả biến
# KHÔNG commit file này lên git nếu có thông tin nhạy cảm
# (thêm terraform.tfvars vào .gitignore)
# ============================================================

# -------------------------------------------------------
# GENERAL
# -------------------------------------------------------
aws_region   = "ap-southeast-1" # Singapore region
aws_profile  = "dev"
project_name = "NT531-Project-Group5"
environment  = "dev"

s3_bucket_name = "nt531-project-group5-bucket"

# -------------------------------------------------------
# VPC & NETWORKING
# -------------------------------------------------------
vpc_cidr = "10.0.0.0/16"

# Public subnets: dùng cho NAT Gateway, Load Balancer, EC2 public instances
public_subnet_cidrs = [
  "10.0.1.0/24", # ap-southeast-1a
  "10.0.2.0/24", # ap-southeast-1b
]

# Private subnets: dùng cho EKS nodes
private_subnet_cidrs = [
  "10.0.11.0/24", # ap-southeast-1a
  "10.0.12.0/24", # ap-southeast-1b
]

availability_zones = [
  "ap-southeast-1a",
  "ap-southeast-1b",
]

# Giới hạn SSH access - thay bằng IP văn phòng/VPN của bạn
# Ví dụ: ["203.0.113.0/24"] hoặc ["0.0.0.0/0"] để test
ssh_allowed_cidrs     = ["0.0.0.0/0"]
grafana_allowed_cidrs = ["0.0.0.0/0"]

# -------------------------------------------------------
# EKS CLUSTER
# -------------------------------------------------------
eks_cluster_version = "1.35"

# API Server access
eks_endpoint_private_access = true
eks_endpoint_public_access  = true
eks_public_access_cidrs     = ["0.0.0.0/0"]

# CloudWatch Logs
eks_enabled_cluster_log_types = ["api", "audit", "authenticator"]
eks_log_retention_days        = 7

# -------------------------------------------------------
# EKS NODE GROUP
# 3 x c5.large nodes như yêu cầu
# c5.large: 2 vCPU, 4GB RAM
# -------------------------------------------------------
eks_node_instance_type   = "c5.large"
eks_node_ami_type        = "AL2_x86_64"
eks_node_disk_size       = 50 # GB per node
eks_node_capacity_type   = "ON_DEMAND"
eks_node_desired_size    = 3
eks_node_min_size        = 1
eks_node_max_size        = 5
eks_node_max_unavailable = 1

eks_node_labels = {
  "role"        = "worker"
  "environment" = "dev"
}

# -------------------------------------------------------
# EC2 INSTANCES: K6 & OBSERVATION
# -------------------------------------------------------

# AMI: để ec2_ami_id = "" để tự động tìm AMI mới nhất
# hoặc chỉ định cụ thể vd: "ami-0df7a207adb9748c7" (Amazon Linux 2 ap-southeast-1)
ec2_ami_id          = "ami-0e7ff22101b84bcff"
ec2_ami_owner       = "amazon"
ec2_ami_name_filter = "amzn2-ami-hvm-*-x86_64-gp2"

# SSH Key Pair - để trống "" để dùng SSM Session Manager (khuyến nghị)
# Nếu muốn dùng SSH key: tạo key pair trên AWS console rồi điền tên vào đây
key_pair_name = "Group5-keypair"
key_pair_path = "./keypair/key.pub"

ec2_enable_detailed_monitoring = false

# K6 Load Testing Instance
# t3.medium: 2 vCPU, 4GB RAM - đủ để chạy K6 với hàng trăm VUs
k6_instance_type = "t3.medium"
k6_volume_type   = "gp3"
k6_volume_size   = 30    # GB
k6_public_ip     = true # Dùng SSM để kết nối, không cần public IP
k6_version       = "0.49.0"

# Observation Instance (OTel Collector + VictoriaMetrics + Grafana)
# t3.medium: 2 vCPU, 4GB RAM - đủ cho observability stack nhẹ
observation_instance_type = "t3.medium"
observation_volume_type   = "gp3"
observation_volume_size   = 50   # GB - cần nhiều hơn cho lưu metrics
observation_public_ip     = true # Cần public IP để truy cập Grafana

# QUAN TRỌNG: Thay đổi mật khẩu Grafana trước khi deploy!
# Trong production: dùng AWS Secrets Manager thay vì hardcode
grafana_admin_user     = "admin"
grafana_admin_password = "admin"
