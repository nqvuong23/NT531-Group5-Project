variable "project_name" {
  # description = "Tên project, dùng làm prefix cho các resource"
  type        = string
}

variable "vpc_cidr" {
  # description = "CIDR block của VPC (vd: 10.0.0.0/16)"
  type        = string
}

variable "public_subnet_cidrs" {
  # description = "Danh sách CIDR cho các public subnet"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  # description = "Danh sách CIDR cho các private subnet"
  type        = list(string)
}

variable "availability_zones" {
  # description = "Danh sách Availability Zones để triển khai subnet"
  type        = list(string)
}

variable "eks_cluster_name" {
  # description = "Tên EKS cluster, dùng để tag subnet cho EKS auto-discovery"
  type        = string
}

variable "ssh_allowed_cidrs" {
  # description = "Danh sách CIDR được phép SSH vào EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "grafana_allowed_cidrs" {
  # description = "Danh sách CIDR được phép truy cập Grafana UI (port 3000)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  # description = "Tags chung áp dụng cho tất cả resource trong module này"
  type        = map(string)
  default     = {}
}
