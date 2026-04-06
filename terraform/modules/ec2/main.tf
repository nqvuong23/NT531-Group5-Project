# ============================================================
# MODULE: ec2
# Tạo 2 EC2 instances:
#   1. K6 - Load testing instance
#   2. Observation - OTel Collector + VictoriaMetrics + Grafana
# ============================================================

# ------- Data source: lấy AMI mới nhất nếu ami_id không được chỉ định -------
data "aws_ami" "selected" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  # Ưu tiên dùng ami_id cố định nếu có, nếu không thì tự động tìm
  resolved_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.selected.id
}

# Upload to S3
resource "aws_s3_object" "docker_compose" {
  bucket = var.s3_bucket_name
  key    = "monitoring/docker-compose.yml"
  source = "${path.module}/monitoring/docker-compose.yml"
  etag   = filemd5("${path.module}/monitoring/docker-compose.yml")

  tags = var.tags
}

resource "aws_s3_object" "otel_collector_config" {
  bucket = var.s3_bucket_name
  key    = "monitoring/config/otel-collector-config.yaml"
  source = "${path.module}/monitoring/config/otel-collector-config.yaml"
  etag   = filemd5("${path.module}/monitoring/config/otel-collector-config.yaml")

  tags = var.tags
}

resource "aws_s3_object" "grafana_datasources" {
  bucket = var.s3_bucket_name
  key    = "monitoring/config/grafana/provisioning/datasources/datasources.yaml"
  source = "${path.module}/monitoring/config/grafana/provisioning/datasources/datasources.yaml"
  etag   = filemd5("${path.module}/monitoring/config/grafana/provisioning/datasources/datasources.yaml")

  tags = var.tags
}

resource "aws_s3_object" "grafana_dashboards_provisioning" {
  bucket = var.s3_bucket_name
  key    = "monitoring/config/grafana/provisioning/dashboards/dashboards.yaml"
  source = "${path.module}/monitoring/config/grafana/provisioning/dashboards/dashboards.yaml"
  etag   = filemd5("${path.module}/monitoring/config/grafana/provisioning/dashboards/dashboards.yaml")

  tags = var.tags
}

resource "aws_s3_object" "grafana_alert_rules" {
  bucket = var.s3_bucket_name
  key    = "monitoring/config/grafana/provisioning/alerting/alert-rules.yaml"
  source = "${path.module}/monitoring/config/grafana/provisioning/alerting/alert-rules.yaml"
  etag   = filemd5("${path.module}/monitoring/config/grafana/provisioning/alerting/alert-rules.yaml")

  tags = var.tags
}

resource "aws_s3_object" "grafana_dashboard_json" {
  bucket = var.s3_bucket_name
  key    = "monitoring/config/grafana/dashboards/microservices-perf.json"
  source = "${path.module}/monitoring/config/grafana/dashboards/microservices-perf.json"
  etag   = filemd5("${path.module}/monitoring/config/grafana/dashboards/microservices-perf.json")

  tags = var.tags
}

# ------- IAM Role cho EC2 (SSM + CloudWatch) -------
resource "aws_iam_role" "ec2_instance_role" {
  name = "${var.project_name}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-ec2-instance-role"
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.ec2_instance_role.name
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name

  tags = merge(var.tags, {
    Name = "${var.project_name}-ec2-instance-profile"
  })
}

resource "aws_iam_policy" "s3_monitoring_read" {
  name        = "${var.project_name}-s3-monitoring-read"
  description = "Allow observation EC2 to read monitoring config files from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadMonitoringConfigs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_monitoring_read" {
  policy_arn = aws_iam_policy.s3_monitoring_read.arn
  role       = aws_iam_role.ec2_instance_role.name
}

# ------- EC2 Instance: K6 Load Testing -------
resource "aws_instance" "k6" {
  ami                    = local.resolved_ami_id
  instance_type          = var.k6_instance_type
  subnet_id              = var.k6_subnet_id
  vpc_security_group_ids = [var.k6_security_group_id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_type           = var.k6_volume_type
    volume_size           = var.k6_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, {
      Name = "${var.project_name}-k6-root-volume"
    })
  }

  # user_data = base64encode(templatefile("${path.module}/templates/k6_userdata.sh.tpl", {
  #   project_name = var.project_name
  #   k6_version   = var.k6_version
  # }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  monitoring = var.enable_detailed_monitoring

  tags = merge(var.tags, {
    Name = "${var.project_name}-k6"
    Role = "load-testing"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ------- EC2 Instance: Observation (OTel + VictoriaMetrics + Grafana) -------
resource "aws_instance" "observation" {
  ami                    = local.resolved_ami_id
  instance_type          = var.observation_instance_type
  subnet_id              = var.observation_subnet_id
  vpc_security_group_ids = [var.observation_security_group_id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_type           = var.observation_volume_type
    volume_size           = var.observation_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, {
      Name = "${var.project_name}-observation-root-volume"
    })
  }

  user_data = base64encode(templatefile("${path.module}/templates/observation_userdata.sh.tpl", {
    project_name           = var.project_name
    grafana_admin_user     = var.grafana_admin_user
    grafana_admin_password = var.grafana_admin_password
    s3_bucket              = var.s3_bucket_name
    aws_region             = var.aws_region
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  monitoring = var.enable_detailed_monitoring

  tags = merge(var.tags, {
    Name = "${var.project_name}-observation"
    Role = "observation"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [
    aws_s3_object.docker_compose,
    aws_s3_object.otel_collector_config,
    aws_s3_object.grafana_datasources,
    aws_s3_object.grafana_dashboards_provisioning,
    aws_s3_object.grafana_alert_rules,
    aws_s3_object.grafana_dashboard_json,
    aws_iam_role_policy_attachment.s3_monitoring_read,
  ]
}

# ------- Elastic IP cho Observation instance (cần public access cho Grafana) -------
resource "aws_eip" "observation" {
  count    = var.observation_public_ip ? 1 : 0
  instance = aws_instance.observation.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-observation-eip"
  })
}

# ------- Elastic IP cho K6 instance (optional) -------
resource "aws_eip" "k6" {
  count    = var.k6_public_ip ? 1 : 0
  instance = aws_instance.k6.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-k6-eip"
  })
}
