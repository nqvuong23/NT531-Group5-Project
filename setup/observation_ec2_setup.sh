#!/bin/bash
# =============================================================================
# setup_observation.sh
# Cấu hình Observation Stack (OTel Collector + VictoriaMetrics + Grafana)
# Chạy thủ công sau khi SSM vào EC2 và đã SCP thư mục observation_ec2_config
# về thư mục ~ của EC2.
#
# Yêu cầu trước khi chạy:
#   1. Đã SCP thư mục observation_ec2_config vào ~ của EC2
#   2. Chỉnh GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD bên dưới nếu cần
#   3. Chạy với sudo: sudo bash setup_observation.sh
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/setup_observation.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
trap 'log "ERROR: dừng tại dòng $LINENO (exit code $?)"' ERR

# ---------- Cấu hình ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/observation_ec2_config"   # thư mục đã SCP vào EC2
MONITOR_DIR="/opt/monitoring"              # thư mục đích trên EC2

GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASSWORD="admin"          # đổi trước khi chạy
# ------------------------------

log "=== Observation EC2 setup bắt đầu ==="


# ── Bước 1: Dừng unattended-upgrades, chờ apt/dpkg rảnh ─────────────────────
log "--- Bước 1: Chờ apt/dpkg rảnh ---"

systemctl stop unattended-upgrades 2>/dev/null || true

_wait=0
while pgrep -f 'apt-get|dpkg|unattended-upgr' >/dev/null 2>&1; do
  if [[ $_wait -ge 120 ]]; then
    log "WARNING: apt/dpkg vẫn bận sau 120s – tiếp tục anyway"
    break
  fi
  log "  apt/dpkg đang bận – chờ 5s (đã chờ: ${_wait}s)"
  sleep 5
  _wait=$((_wait + 5))
done
log "apt/dpkg đã rảnh sau ${_wait}s"


# ── Bước 2: Cài Docker Engine (official apt repo) ────────────────────────────
log "--- Bước 2: Cài Docker Engine ---"

# Xóa các package Docker cũ nếu có
for pkg in docker.io docker-doc docker-compose docker-compose-v2 \
            podman-docker containerd runc; do
  apt-get remove -y "$pkg" 2>/dev/null || true
done

apt-get update -y
apt-get install -y ca-certificates curl

# Thêm GPG key chính thức của Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME}")

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl start docker

# Thêm user ubuntu vào group docker để debug không cần sudo
usermod -aG docker ubuntu

log "Docker:         $(docker --version)"
log "Docker Compose: $(docker compose version)"


# ── Bước 3: Copy thư mục config từ ~/observation_ec2_config ──────────────────
log "--- Bước 3: Copy config files từ ${SRC_DIR} → ${MONITOR_DIR} ---"

if [[ ! -d "$SRC_DIR" ]]; then
  log "ERROR: Không tìm thấy thư mục nguồn: $SRC_DIR"
  log "       Hãy SCP thư mục observation_ec2_config vào ~ trước khi chạy script này."
  exit 1
fi

# Tạo cấu trúc thư mục đích
mkdir -p \
  "${MONITOR_DIR}/config/grafana/provisioning/datasources" \
  "${MONITOR_DIR}/config/grafana/provisioning/dashboards" \
  "${MONITOR_DIR}/config/grafana/provisioning/alerting" \
  "${MONITOR_DIR}/config/grafana/dashboards"

# Copy toàn bộ nội dung từ nguồn sang đích
cp -r "${SRC_DIR}/." "${MONITOR_DIR}/"

log "Copy hoàn tất. Nội dung ${MONITOR_DIR}:"
ls -lh "${MONITOR_DIR}"


# ── Bước 4: Tạo file .env chứa Grafana credentials ───────────────────────────
log "--- Bước 4: Tạo .env ---"

cat > "${MONITOR_DIR}/.env" <<EOF
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
EOF

chmod 600 "${MONITOR_DIR}/.env"
chown root:root "${MONITOR_DIR}/.env"

log ".env đã tạo (mode 600, owner root:root)"


# ── Bước 5: Pull images và khởi động monitoring stack ────────────────────────
log "--- Bước 5: Khởi động monitoring stack ---"

cd "${MONITOR_DIR}"

log "Pulling Docker images (lần đầu có thể mất 2-3 phút)..."
docker compose pull || log "WARNING: 'docker compose pull' thất bại – thử start với cached images"

docker compose up -d
log "Containers đã start"

# Kiểm tra nhanh status
sleep 5
log "Container status hiện tại:"
docker compose ps


# ── Bước 6: Tạo systemd unit để auto-restart khi EC2 reboot ──────────────────
log "--- Bước 6: Tạo systemd unit monitoring-stack ---"

cat > /etc/systemd/system/monitoring-stack.service <<'UNIT'
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
UNIT

systemctl daemon-reload
systemctl enable monitoring-stack
log "systemd unit 'monitoring-stack' đã enable (tự start khi reboot)"


# ── Done: In thông tin endpoint ───────────────────────────────────────────────
IMDS_TOKEN=$(curl -s \
  -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
  --max-time 5 2>/dev/null || true)

if [[ -n "$IMDS_TOKEN" ]]; then
  PUBLIC_IP=$(curl -s \
    -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    "http://169.254.169.254/latest/meta-data/public-ipv4" \
    --max-time 5 2>/dev/null || echo "<unknown>")
else
  PUBLIC_IP="<unknown>"
fi

log ""
log "================================================================"
log "=== Setup hoàn tất! ==="
log "================================================================"
log "Grafana             → http://${PUBLIC_IP}:3000"
log "VictoriaMetrics     → http://${PUBLIC_IP}:8428"
log "OTel Collector gRPC → ${PUBLIC_IP}:4317"
log "OTel Collector HTTP → ${PUBLIC_IP}:4318"
log "Log đầy đủ          → /var/log/setup_observation.log"
log "================================================================"