variable "project_name" {
  # description = "Tên project, dùng làm prefix cho các resource"
  type        = string
}

variable "cluster_name" {
  # description = "Tên của EKS cluster"
  type        = string
}

variable "cluster_version" {
  # description = "Phiên bản Kubernetes cho EKS cluster (vd: 1.29)"
  type        = string
}

variable "subnet_ids" {
  # description = "Danh sách subnet IDs cho EKS control plane (nên có cả public và private)"
  type        = list(string)
}

variable "node_subnet_ids" {
  # description = "Danh sách subnet IDs cho worker nodes (nên là private subnets)"
  type        = list(string)
}

variable "cluster_security_group_id" {
  # description = "ID của Security Group cho EKS control plane"
  type        = string
}

variable "nodes_security_group_id" {
  # description = "ID của Security Group cho EKS worker nodes"
  type        = string
}

variable "endpoint_private_access" {
  # description = "Bật private API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  # description = "Bật public API server endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  # description = "Danh sách CIDR được phép truy cập public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  # description = "Các loại log EKS cần gửi lên CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  # description = "Số ngày giữ log trong CloudWatch"
  type        = number
  default     = 7
}

# ------- Node Group Variables -------
variable "node_instance_type" {
  # description = "Instance type cho EKS worker nodes (vd: c5.large)"
  type        = string
}

variable "node_ami_type" {
  # description = "Loại AMI cho nodes (AL2_x86_64, AL2_x86_64_GPU, BOTTLEROCKET_x86_64, ...)"
  type        = string
  default     = "AL2_x86_64"
}

variable "node_disk_size" {
  # description = "Dung lượng ổ đĩa (GB) cho mỗi worker node"
  type        = number
  default     = 50
}

variable "node_capacity_type" {
  # description = "Loại capacity: ON_DEMAND hoặc SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  # description = "Số lượng node mong muốn"
  type        = number
  default     = 3
}

variable "node_min_size" {
  # description = "Số lượng node tối thiểu"
  type        = number
  default     = 1
}

variable "node_max_size" {
  # description = "Số lượng node tối đa"
  type        = number
  default     = 5
}

variable "node_max_unavailable" {
  # description = "Số node tối đa có thể unavailable khi update"
  type        = number
  default     = 1
}

variable "node_key_pair_name" {
  # description = "Tên EC2 Key Pair để SSH vào nodes (để trống nếu không cần)"
  type        = string
  default     = ""
}

variable "node_labels" {
  # description = "Kubernetes labels gắn lên các node"
  type        = map(string)
  default     = {}
}

variable "tags" {
  # description = "Tags chung áp dụng cho tất cả resource trong module này"
  type        = map(string)
  default     = {}
}
