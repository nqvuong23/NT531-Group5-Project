#!/bin/bash
# =============================================================================
# install_k6.sh
# Cài đặt k6 load testing tool trên Ubuntu EC2
# Nguồn tham khảo: https://grafana.com/docs/k6/latest/set-up/install-k6/
#
# Chạy với sudo: sudo bash install_k6.sh
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/install_k6.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
trap 'log "ERROR: dừng tại dòng $LINENO (exit code $?)"' ERR

log "=== Bắt đầu cài đặt k6 ==="


# ── Bước 1: Cài các package cần thiết ────────────────────────────────────────
log "--- Bước 1: Cài dependencies ---"

apt-get update -y
apt-get install -y gnupg curl


# ── Bước 2: Thêm GPG key và apt repo chính thức của k6 ───────────────────────
log "--- Bước 2: Thêm k6 apt repo ---"

gpg -k
gpg --no-default-keyring \
    --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
    --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69

echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | tee /etc/apt/sources.list.d/k6.list


# ── Bước 3: Cài k6 ───────────────────────────────────────────────────────────
log "--- Bước 3: Cài k6 ---"

apt-get update -y
apt-get install -y k6


# ── Bước 4: Kiểm tra cài đặt ─────────────────────────────────────────────────
log "--- Bước 4: Kiểm tra ---"

k6 version

log ""
log "================================================================"
log "=== k6 cài đặt thành công! ==="
log "================================================================"
log "Phiên bản: $(k6 version)"
log "Binary:    $(which k6)"
log ""
log "Ví dụ chạy test nhanh:"
log "  k6 run --vus 5 --duration 10s <script.js>"
log "Log đầy đủ → /var/log/install_k6.log"
log "================================================================"

log "--- Bước 5: Cài Docker Engine ---"

log "=== Bắt đầu cài đặt docker + docker compose ==="

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

# ---------- Cấu hình ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/sources"   

cd "${SRC_DIR}"

log "Pulling Docker images (lần đầu có thể mất 2-3 phút)..."
docker compose pull || log "WARNING: 'docker compose pull' thất bại – thử start với cached images"

docker compose up -d
log "Containers đã start"

# Kiểm tra nhanh status
sleep 5
log "Container status hiện tại:"
docker compose ps

log "--- Bước 6: Tạo systemd unit monitoring-stack ---"

cat > /etc/systemd/system/monitoring-stack.service <<UNIT
[Unit]
Description=Monitoring Stack — OTel Agent on K6
Documentation=file://${SRC_DIR}/docker-compose.yml
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${SRC_DIR}
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


