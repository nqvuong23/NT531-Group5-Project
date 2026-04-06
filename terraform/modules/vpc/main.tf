# ============================================================
# MODULE: vpc
# Tạo VPC với public/private subnets, IGW, NAT Gateway,
# Route Tables và các Security Group nền tảng
# ============================================================

# ------- VPC -------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc"
  })
}

# ------- Internet Gateway -------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw"
  })
}

# ------- Public Subnets -------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                            = "${var.project_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  })
}

# ------- Private Subnets -------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                                            = "${var.project_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  })
}

# ------- Elastic IP cho NAT Gateway -------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

# ------- NAT Gateway (đặt ở public subnet đầu tiên) -------
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat-gw"
  })

  depends_on = [aws_internet_gateway.main]
}

# ------- Route Table: Public -------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ------- Route Table: Private -------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ------- Security Group: EKS Cluster -------
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  # description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.main.id

  ingress {
    # description = "HTTPS from node group"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    # description = "HTTP from node group"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    # description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-eks-cluster-sg"
  })
}

# ------- Security Group: EKS Node Group -------
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  # description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    # description = "Internal communication between nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    # description     = "Control plane giao tiếp với nodes"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  ingress {
    # description     = "HTTPS từ control plane"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  ingress {
    # description = "Internal NLB → Nginx (port 80)"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    # description     = "Observation EC2 → Node Exporter"
    from_port = 9100
    to_port = 9100
    protocol = "tcp"
    security_groups = [aws_security_group.observation.id]
  }

  egress {
    # description = "Cho phép tất cả outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-eks-nodes-sg"
  })
}

# ------- Security Group: K6 Load Testing Instance -------
resource "aws_security_group" "k6" {
  name        = "${var.project_name}-k6-sg"
  # description = "Security group cho K6 load testing instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    # description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    # description = "Cho phép tất cả outbound (cần để gửi traffic test)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-k6-sg"
  })
}

# ------- Security Group: Observation Instance -------
resource "aws_security_group" "observation" {
  name        = "${var.project_name}-observation-sg"
  # description = "Security group cho Observation instance (OTel, VictoriaMetrics, Grafana)"
  vpc_id      = aws_vpc.main.id

  ingress {
    # description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    # description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.grafana_allowed_cidrs
  }

  ingress {
    # description = "VictoriaMetrics HTTP (internal VPC)"
    from_port   = 8428
    to_port     = 8428
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    # description = "VictoriaMetrics HTTP (external verify)"
    from_port = 8428
    to_port = 8428
    protocol = "tcp"
    cidr_blocks = var.grafana_allowed_cidrs
  }

  ingress {
    # description = "OpenTelemetry Collector gRPC"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    # description = "OpenTelemetry Collector HTTP"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    # description = "OTel Collector self-metrics"
    from_port = 8888
    to_port = 8888
    protocol = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    # description = "Prometheus remote write vào VictoriaMetrics"
    from_port   = 8480
    to_port     = 8480
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    # description = "Cho phép tất cả outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-observation-sg"
  })
}
