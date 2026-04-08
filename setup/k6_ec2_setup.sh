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