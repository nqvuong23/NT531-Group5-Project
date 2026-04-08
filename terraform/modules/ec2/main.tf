# ============================================================
# MODULE: ec2
# Tạo 2 EC2 instances:
#   1. K6 - Load testing instance
#   2. Observation - OTel Collector + VictoriaMetrics + Grafana
# ============================================================

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

# ------- EC2 Instance: K6 Load Testing -------
resource "aws_instance" "k6" {
  ami                    = var.ami_id
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
  ami                    = var.ami_id
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
