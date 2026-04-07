#!/bin/bash

# Ghi log ra file và console đồng thời
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Dừng ngay nếu có lỗi
set -euo pipefail

cloud-init status --wait

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Observation EC2 setup started (project: ${project_name}) ==="

# BƯỚC 1.1: Cài Docker Engine (official Ubuntu method)
log "--- Step 1.1: Install Docker Engine ---"

# Xóa các package cũ/unofficial có thể conflict
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y "$$pkg" 2>/dev/null || true
done

# Cập nhật apt và cài các package cần thiết để thêm Docker repo
apt-get update -y
apt-get install -y ca-certificates curl unzip

# Thêm Docker official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Thêm Docker apt repository
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $$(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Cài Docker Engine + Docker Compose plugin (V2)
apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# Enable và start Docker daemon
systemctl enable docker
systemctl start docker

# Thêm ubuntu user vào docker group — cho debug thủ công sau này
usermod -aG docker ubuntu

log "Docker: $$(docker --version)"
log "Docker Compose: $$(docker compose version)"

# BƯỚC 1.2: Install AWS CLI
log "--- Step 1.2: Install AWS CLI ---"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# BƯỚC 2: Tạo cấu trúc thư mục /opt/monitoring/
log "--- Step 2: Create directory structure ---"

MONITOR_DIR="/opt/monitoring"

mkdir -p "$${MONITOR_DIR}/config/grafana/provisioning/datasources"
mkdir -p "$${MONITOR_DIR}/config/grafana/provisioning/dashboards"
mkdir -p "$${MONITOR_DIR}/config/grafana/provisioning/alerting"
mkdir -p "$${MONITOR_DIR}/config/grafana/dashboards"

log "Directory structure created at $${MONITOR_DIR}"

# BƯỚC 3: Download config files từ S3
log "--- Step 3: Download config files from S3 (s3://${s3_bucket}/monitoring/) ---"

export AWS_DEFAULT_REGION="${aws_region}"

# Hàm download với retry (xử lý IAM propagation delay ~10-15s sau khi EC2 boot)
s3_download() {
  local src="$$1"
  local dst="$$2"
  local max_attempts=6
  local attempt=1

  while [[ $$attempt -le $$max_attempts ]]; do
    if aws s3 cp "$$src" "$$dst" --region "${aws_region}" 2>/dev/null; then
      log "  OK: $$src → $$dst"
      return 0
    fi
    log "  Attempt $$attempt/$$max_attempts failed for $$src — retrying in 10s..."
    sleep 10
    attempt=$$((attempt + 1))
  done

  log "  ERROR: Failed to download $$src after $$max_attempts attempts"
  return 1
}

S3_BASE="s3://${s3_bucket}/monitoring"

s3_download "$${S3_BASE}/docker-compose.yml" \
            "$${MONITOR_DIR}/docker-compose.yml"

s3_download "$${S3_BASE}/config/otel-collector-config.yaml" \
            "$${MONITOR_DIR}/config/otel-collector-config.yaml"

s3_download "$${S3_BASE}/config/grafana/provisioning/datasources/datasources.yaml" \
            "$${MONITOR_DIR}/config/grafana/provisioning/datasources/datasources.yaml"

s3_download "$${S3_BASE}/config/grafana/provisioning/dashboards/dashboards.yaml" \
            "$${MONITOR_DIR}/config/grafana/provisioning/dashboards/dashboards.yaml"

s3_download "$${S3_BASE}/config/grafana/provisioning/alerting/alert-rules.yaml" \
            "$${MONITOR_DIR}/config/grafana/provisioning/alerting/alert-rules.yaml"

s3_download "$${S3_BASE}/config/grafana/dashboards/microservices-perf.json" \
            "$${MONITOR_DIR}/config/grafana/dashboards/microservices-perf.json"

log "All config files downloaded"

# Verify: đảm bảo tất cả file tồn tại trước khi tiếp tục
REQUIRED_FILES=(
  "$${MONITOR_DIR}/docker-compose.yml"
  "$${MONITOR_DIR}/config/otel-collector-config.yaml"
  "$${MONITOR_DIR}/config/grafana/provisioning/datasources/datasources.yaml"
  "$${MONITOR_DIR}/config/grafana/provisioning/dashboards/dashboards.yaml"
  "$${MONITOR_DIR}/config/grafana/provisioning/alerting/alert-rules.yaml"
  "$${MONITOR_DIR}/config/grafana/dashboards/microservices-perf.json"
)

for f in "$${REQUIRED_FILES[@]}"; do
  [[ -f "$$f" ]] || { log "ERROR: Missing required file: $$f"; exit 1; }
done
log "All required files verified"

# BƯỚC 4: Tạo file .env với Grafana credentials
log "--- Step 4: Create .env file ---"

cat > "$${MONITOR_DIR}/.env" << ENVEOF
GRAFANA_ADMIN_USER=${grafana_admin_user}
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}
ENVEOF

# Chỉ ubuntu user và root được đọc file này (chứa password)
chmod 600 "$${MONITOR_DIR}/.env"
chown root:root "$${MONITOR_DIR}/.env"

log ".env created (credentials injected by Terraform)"

# BƯỚC 5: Khởi động monitoring stack
log "--- Step 5: Start monitoring stack ---"

cd "$${MONITOR_DIR}"

# Pull images trước — tách biệt lỗi mạng khỏi lỗi config
# Khoảng 3 images tổng ~1.5GB — có thể mất 2-3 phút
log "Pulling Docker images (may take 2-3 minutes)..."
docker compose pull

# Start tất cả services
docker compose up -d

log "Containers started, waiting for health checks..."

# BƯỚC 6: Chờ từng container healthy
log "--- Step 6: Wait for containers healthy ---"

wait_healthy() {
  local container="$$1"
  local max_wait="$$2"   # giây
  local elapsed=0
  local interval=5

  while [[ $$elapsed -lt $$max_wait ]]; do
    STATUS=$$(docker inspect --format='{{.State.Health.Status}}' "$$container" 2>/dev/null || echo "not_found")
    case "$$STATUS" in
      healthy)
        log "  $$container: healthy ✓ ($$elapsed s)"
        return 0
        ;;
      unhealthy)
        log "  $$container: UNHEALTHY — check logs: docker logs $$container"
        return 1
        ;;
      not_found)
        log "  $$container: container not found"
        return 1
        ;;
    esac
    sleep $$interval
    elapsed=$$((elapsed + interval))
  done

  log "  WARNING: $$container still '$$STATUS' after $${max_wait}s"
  return 1
}

# VictoriaMetrics phải healthy trước vì otel-collector và grafana depends_on nó
wait_healthy "victoriametrics" 60 || true
wait_healthy "otel-collector"  90 || true
wait_healthy "grafana"         90 || true

# In trạng thái tất cả containers
log "Current container status:"
docker compose ps

# BƯỚC 7: Tạo systemd unit để auto-restart khi EC2 reboot
log "--- Step 7: Create systemd unit for auto-restart on reboot ---"

cat > /etc/systemd/system/monitoring-stack.service << 'UNITEOF'
[Unit]
Description=Monitoring Stack — OTel Collector + VictoriaMetrics + Grafana
Documentation=file:///opt/monitoring/docker-compose.yml
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/monitoring
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
TimeoutStopSec=60
Restart=no

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable monitoring-stack
log "systemd unit 'monitoring-stack' enabled (will auto-start on reboot)"

# Done — lấy public IP (IMDSv2) để in URL truy cập
TOKEN=$$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
  --max-time 5 2>/dev/null || echo "")

if [[ -n "$$TOKEN" ]]; then
  PUBLIC_IP=$$(curl -s \
    -H "X-aws-ec2-metadata-token: $$TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4 \
    --max-time 5 2>/dev/null || echo "<unknown>")
else
  PUBLIC_IP="<unknown>"
fi
