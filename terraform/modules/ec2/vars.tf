variable "project_name" {
  # description = "Tên project, dùng làm prefix cho các resource"
  type        = string
}

variable "aws_region" {
  # description = "AWS region để triển khai hạ tầng (vd: ap-southeast-1)"
  type = string
}

variable "s3_bucket_name" {
  type = string
}

# ------- AMI Variables -------
variable "ami_id" {
  # description = "AMI ID cố định (để trống '' để tự động tìm AMI mới nhất theo filter)"
  type        = string
  default     = ""
}

variable "ami_owner" {
  # description = "Owner của AMI khi tự động tìm (vd: amazon, 099720109477 cho Ubuntu)"
  type        = string
  default     = "amazon"
}

variable "ami_name_filter" {
  # description = "Pattern tên AMI để tìm kiếm (vd: amzn2-ami-hvm-*-x86_64-gp2)"
  type        = string
  default     = "amzn2-ami-hvm-*-x86_64-gp2"
}

# ------- K6 Instance Variables -------
variable "k6_instance_type" {
  # description = "Instance type cho K6 load testing (vd: t3.medium)"
  type        = string
}

variable "k6_subnet_id" {
  # description = "Subnet ID để đặt K6 instance"
  type        = string
}

variable "k6_security_group_id" {
  # description = "Security Group ID cho K6 instance"
  type        = string
}

variable "k6_volume_type" {
  # description = "Loại EBS volume cho K6 instance (gp3, gp2, io1...)"
  type        = string
  default     = "gp3"
}

variable "k6_volume_size" {
  # description = "Dung lượng ổ đĩa (GB) cho K6 instance"
  type        = number
  default     = 30
}

variable "k6_public_ip" {
  # description = "Gán Elastic IP public cho K6 instance hay không"
  type        = bool
  default     = false
}

variable "k6_version" {
  # description = "Phiên bản K6 để cài đặt (vd: 0.49.0)"
  type        = string
  default     = "0.49.0"
}

# ------- Observation Instance Variables -------
variable "observation_instance_type" {
  # description = "Instance type cho Observation instance (vd: t3.medium)"
  type        = string
}

variable "observation_subnet_id" {
  # description = "Subnet ID để đặt Observation instance"
  type        = string
}

variable "observation_security_group_id" {
  # description = "Security Group ID cho Observation instance"
  type        = string
}

variable "observation_volume_type" {
  # description = "Loại EBS volume cho Observation instance"
  type        = string
  default     = "gp3"
}

variable "observation_volume_size" {
  # description = "Dung lượng ổ đĩa (GB) cho Observation instance (cần nhiều hơn cho metrics storage)"
  type        = number
  default     = 50
}

variable "observation_public_ip" {
  # description = "Gán Elastic IP public cho Observation instance (để truy cập Grafana)"
  type        = bool
  default     = true
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  # description = "Mật khẩu admin cho Grafana"
  type        = string
  sensitive   = true
  default = "admin"
}

variable "victoriametrics_version" {
  # description = "Phiên bản VictoriaMetrics để cài đặt (vd: 1.93.12)"
  type        = string
  default     = "1.93.12"
}

variable "otel_collector_version" {
  # description = "Phiên bản OpenTelemetry Collector để cài đặt (vd: 0.92.0)"
  type        = string
  default     = "0.92.0"
}

# ------- Common EC2 Variables -------
variable "key_pair_name" {
  # description = "Tên EC2 Key Pair để SSH vào instances (để trống nếu dùng SSM)"
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  # description = "Bật CloudWatch detailed monitoring (1 phút interval, có phí thêm)"
  type        = bool
  default     = false
}

variable "tags" {
  # description = "Tags chung áp dụng cho tất cả resource trong module này"
  type        = map(string)
  default     = {}
}
