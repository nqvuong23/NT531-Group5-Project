#!/usr/bin/env bash
# ============================================================
# setup.sh — Master Setup Script
# Chạy 1 lần từ máy tính của người dùng sau khi clone repo.
#
# Thứ tự thực hiện:
#   1. Kiểm tra tools (terraform, kubectl, aws-cli, jq)
#   2. Kiểm tra AWS credentials
#   3. terraform init + apply
#      → EC2 observation khởi động + chạy userdata tự động
#        (cài Docker, download S3, chạy docker compose)
#   4. Cập nhật kubeconfig + gán label/taint cho 3 EKS nodes
#   5. Apply microservice manifests (k8s-microservices/)
#   6. Lấy External DNS của Nginx LoadBalancer
#   7. Apply monitoring K8s resources (DaemonSets) + chờ
#      observation EC2 healthy
#   8. Xuất biến quan trọng ra file .env.output
#
# CÁCH DÙNG:
#   chmod +x setup/setup.sh
#   ./setup/setup.sh
# ============================================================

set -euo pipefail

# -------------------------------------------------------
# Constants & Paths
# -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
MICROSERVICES_K8S_DIR="${PROJECT_ROOT}/k8s/microservices"
MONITORING_K8S_DIR="${PROJECT_ROOT}/k8s/monitoring"

CLUSTER_NAME="${CLUSTER_NAME:-NT531-Project-Group5-dev-eks}"
REGION="${AWS_REGION:-ap-southeast-1}"
PROFILE="${AWS_PROFILE:-dev}"

OUTPUT_ENV_FILE="${PROJECT_ROOT}/.env.output"

# -------------------------------------------------------
# Colors
# -------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

step()    { echo -e "\n${BOLD}${BLUE}══════ $* ══════${NC}"; }
info()    { echo -e "  ${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $*"; }
error()   { echo -e "  ${RED}[✗]${NC} $*" >&2; exit 1; }
running() { echo -e "  ${CYAN}[→]${NC} $*"; }

# -------------------------------------------------------
# BƯỚC 1: Kiểm tra tools bắt buộc
# -------------------------------------------------------
step "BƯỚC 1: Kiểm tra prerequisites"

MISSING_TOOLS=()
for tool in terraform kubectl aws jq; do
  if command -v "$tool" &>/dev/null; then
    VER=$(${tool} version 2>/dev/null | head -1 || ${tool} --version 2>/dev/null | head -1 || echo "unknown")
    info "$tool: $VER"
  else
    MISSING_TOOLS+=("$tool")
    echo -e "  ${RED}[✗]${NC} $tool: NOT FOUND"
  fi
done

[[ ${#MISSING_TOOLS[@]} -gt 0 ]] && \
  error "Thiếu tools: ${MISSING_TOOLS[*]}. Cài đặt rồi chạy lại."

# -------------------------------------------------------
# BƯỚC 2: Kiểm tra AWS credentials
# -------------------------------------------------------
step "BƯỚC 2: Kiểm tra AWS credentials"

if aws sts get-caller-identity --profile "$PROFILE" \
     --output json 2>/dev/null | jq -r '.Arn' > /dev/null 2>&1; then
  CALLER_ARN=$(aws sts get-caller-identity --profile "$PROFILE" \
    --output json 2>/dev/null | jq -r '.Arn')
  info "Authenticated as: $CALLER_ARN"
elif aws sts get-caller-identity --output json 2>/dev/null | jq -r '.Arn' > /dev/null 2>&1; then
  CALLER_ARN=$(aws sts get-caller-identity --output json 2>/dev/null | jq -r '.Arn')
  PROFILE=""
  info "Authenticated via environment vars: $CALLER_ARN"
else
  error "Không có AWS credentials hợp lệ. Chạy 'aws configure' hoặc set AWS env vars."
fi

PROFILE_ARG=""
[[ -n "$PROFILE" ]] && PROFILE_ARG="--profile $PROFILE"

# -------------------------------------------------------
# BƯỚC 3: Terraform init + apply
# -------------------------------------------------------
step "BƯỚC 3: Terraform apply"

[[ ! -d "$TERRAFORM_DIR" ]] && error "Không tìm thấy $TERRAFORM_DIR"

cd "$TERRAFORM_DIR"
running "terraform init..."
terraform init

running "terraform apply (auto-approve)..."
terraform apply -auto-approve

info "Terraform apply hoàn thành"

running "Đọc terraform outputs..."

OBSERVATION_PRIVATE_IP=$(terraform output -raw observation_private_ip 2>/dev/null || echo "")
OBSERVATION_PUBLIC_IP=$(terraform output -raw observation_public_ip 2>/dev/null || echo "")

K6_PRIVATE_IP=$(terraform output -raw k6_private_ip 2>/dev/null || echo "")
# K6_PUBLIC_IP=$(terraform output -raw k6_public_ip 2>/dev/null || echo "")

TF_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "$CLUSTER_NAME")

[[ -n "$TF_CLUSTER_NAME" ]] && CLUSTER_NAME="$TF_CLUSTER_NAME"

if [[ -z "$OBSERVATION_PRIVATE_IP" ]]; then
  warn "Không đọc được observation_private_ip từ terraform output."
  warn "Nhập Private IP của EC2 monitoring (bắt buộc cho ConfigMap patch):"
  read -r OBSERVATION_PRIVATE_IP || true
fi

if [[ -z "$OBSERVATION_PUBLIC_IP" ]]; then
  warn "Không đọc được observation_public_ip. Nhập (hoặc Enter bỏ qua):"
  read -r OBSERVATION_PUBLIC_IP || true
fi

if [[ -z "$K6_PRIVATE_IP" ]]; then
  warn "Không đọc được k6_private_ip từ terraform output."
  warn "Nhập Private IP của EC2 monitoring (bắt buộc cho ConfigMap patch):"
  read -r K6_PRIVATE_IP || true
fi

# if [[ -z "$K6_PUBLIC_IP" ]]; then
#   warn "Không đọc được k6_public_ip. Nhập (hoặc Enter bỏ qua):"
#   read -r K6_PUBLIC_IP || true
# fi

info "EKS Cluster:          $CLUSTER_NAME"
info "Observation Private:  ${OBSERVATION_PRIVATE_IP:-N/A}"
info "Observation Public:   ${OBSERVATION_PUBLIC_IP:-N/A}"
info "K6 Private:           ${K6_PRIVATE_IP:-N/A}"
# info "K6 Public:            ${K6_PUBLIC_IP:-N/A}"

cd "$PROJECT_ROOT"

# -------------------------------------------------------
# BƯỚC 4: Cập nhật kubeconfig + gán label/taint cho nodes
# -------------------------------------------------------
step "BƯỚC 4: Kubeconfig + Node labeling"

running "Cập nhật kubeconfig..."
aws eks update-kubeconfig \
  --region  "$REGION" \
  --name    "$CLUSTER_NAME" \
  ${PROFILE_ARG} 2>/dev/null || \
aws eks update-kubeconfig \
  --region "$REGION" \
  --name   "$CLUSTER_NAME"
info "kubeconfig cập nhật xong"

running "Chờ 3 EKS nodes Ready..."
TIMEOUT=300; ELAPSED=0
while true; do
  READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
  [[ "$READY_COUNT" -ge 3 ]] && { info "Đủ 3 nodes Ready"; break; }
  [[ "$ELAPSED" -ge "$TIMEOUT" ]] && error "Timeout: chỉ có $READY_COUNT/3 node Ready"
  warn "Hiện có $READY_COUNT/3 node Ready — chờ 10s... (${ELAPSED}s/${TIMEOUT}s)"
  sleep 10; ELAPSED=$((ELAPSED + 10))
done

mapfile -t NODE_ARRAY < <(kubectl get nodes --no-headers \
  -o custom-columns="NAME:.metadata.name" | sort)

GATEWAY_NODE="${NODE_ARRAY[0]}"
SERVICE_A_NODE="${NODE_ARRAY[1]}"
SERVICE_B_NODE="${NODE_ARRAY[2]}"

echo ""
running "Phân bổ nodes:"
printf "  %-16s → %s\n" "Gateway (Nginx)"   "$GATEWAY_NODE"
printf "  %-16s → %s\n" "Node A (front)"    "$SERVICE_A_NODE"
printf "  %-16s → %s\n" "Node B (back)"     "$SERVICE_B_NODE"
echo ""

for node in "${NODE_ARRAY[@]}"; do
  kubectl label node "$node" role- --overwrite 2>/dev/null || true
  kubectl taint node "$node" role- 2>/dev/null || true
done

kubectl label node "$GATEWAY_NODE"   role=gateway   --overwrite
kubectl taint node "$GATEWAY_NODE"   role=gateway:NoSchedule --overwrite
kubectl label node "$SERVICE_A_NODE" role=node-a --overwrite
kubectl label node "$SERVICE_B_NODE" role=node-b --overwrite

info "Labels và taints đã gán"
kubectl get nodes -L role --no-headers | \
  awk '{printf "    %-55s %s\n", $1, $NF}'

# -------------------------------------------------------
# BƯỚC 5: Apply microservice K8s manifests
# -------------------------------------------------------
step "BƯỚC 5: Apply microservice manifests"

[[ ! -d "$MICROSERVICES_K8S_DIR" ]] && error "Không tìm thấy $MICROSERVICES_K8S_DIR"

running "Applying kubernetes-manifests.yaml..."
kubectl apply -f "${MICROSERVICES_K8S_DIR}/kubernetes-manifests.yaml"

running "Applying nginx-gateway.yaml..."
kubectl apply -f "${MICROSERVICES_K8S_DIR}/nginx-gateway.yaml"

running "Chờ nginx-gateway rollout..."
kubectl rollout status deployment/nginx-gateway --timeout=120s || \
  warn "nginx-gateway chưa ready sau 120s — tiếp tục"

info "Microservice manifests applied"

# -------------------------------------------------------
# BƯỚC 6: Lấy External DNS/IP của Nginx LoadBalancer
# -------------------------------------------------------
step "BƯỚC 6: Lấy Nginx LoadBalancer endpoint"

running "Chờ LoadBalancer external hostname/IP (tối đa 5 phút)..."
NGINX_LB=""
for i in $(seq 1 30); do
  NGINX_LB=$(kubectl get svc nginx-gateway \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  [[ -z "$NGINX_LB" ]] && \
    NGINX_LB=$(kubectl get svc nginx-gateway \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [[ -n "$NGINX_LB" ]] && break
  [[ $i -eq 30 ]] && { warn "Không lấy được Nginx LB endpoint — kiểm tra sau"; break; }
  sleep 10
done

if [[ -n "$NGINX_LB" ]]; then
  info "Nginx LoadBalancer endpoint: $NGINX_LB"
  info "(Dùng endpoint này làm FRONTEND_ADDR cho k6 script)"
else
  warn "Nginx LB chưa có endpoint. Kiểm tra: kubectl get svc nginx-gateway"
fi

# -------------------------------------------------------
# BƯỚC 7: Apply monitoring K8s resources + chờ EC2 healthy
# -------------------------------------------------------
step "BƯỚC 7: Deploy monitoring trên EKS + xác nhận EC2 healthy"

[[ ! -d "$MONITORING_K8S_DIR" ]] && \
  { warn "Không tìm thấy $MONITORING_K8S_DIR — bỏ qua"; } || {

  # Tạo namespace monitoring
  running "Creating monitoring namespace..."
  kubectl apply -f "${MONITORING_K8S_DIR}/monitoring-namespace.yaml"

  # Apply OTel Agent DaemonSet (tạo ConfigMap với placeholder trước)
  running "Applying otel-agent-daemonset.yaml..."
  kubectl apply -f "${MONITORING_K8S_DIR}/otel-agent-daemonset.yaml"

  # Patch ConfigMap với private IP thực của EC2 monitoring
  if [[ -n "$OBSERVATION_PRIVATE_IP" ]]; then
    running "Patching monitoring-endpoints ConfigMap: http://${OBSERVATION_PRIVATE_IP}:4317"
    kubectl -n monitoring patch configmap monitoring-endpoints \
      --type merge \
      -p "{\"data\":{\"otel_collector_endpoint\":\"http://${OBSERVATION_PRIVATE_IP}:4317\"}}"
    info "ConfigMap patched"
  else
    warn "Không có IP EC2 monitoring — patch ConfigMap thủ công sau:"
    warn "  kubectl -n monitoring patch configmap monitoring-endpoints \\"
    warn "    --type merge -p '{\"data\":{\"otel_collector_endpoint\":\"http://<IP>:4317\"}}'"
  fi

  running "Applying node-exporter-daemonset.yaml..."
  kubectl apply -f "${MONITORING_K8S_DIR}/node-exporter-daemonset.yaml"

  # Restart OTel Agent để pick up config mới
  running "Restarting otel-agent DaemonSet..."
  kubectl -n monitoring rollout restart daemonset/otel-agent 2>/dev/null || true

  info "Chờ DaemonSets ready..."
  kubectl -n monitoring rollout status daemonset/node-exporter --timeout=180s || \
    warn "node-exporter chưa ready sau 180s"
  kubectl -n monitoring rollout status daemonset/otel-agent    --timeout=180s || \
    warn "otel-agent chưa ready sau 180s"

  # ----------------------------------------------------------
  # Chờ OTel Collector trên EC2 healthy
  # [THAY ĐỔI so với bản cũ] Không cần SSH/SCP nữa.
  # Chỉ poll health check endpoint :13133 để xác nhận userdata
  # (Docker Compose) đã hoàn thành trên EC2.
  #
  # Timeline dự kiến từ khi terraform apply xong:
  #   ~2 min  : EC2 boot + yum install docker
  #   ~3 min  : docker compose pull (download images ~1.5GB)
  #   ~4 min  : containers up + healthy
  # → Chờ tối đa 10 phút là đủ trong hầu hết trường hợp.
  # ----------------------------------------------------------
  if [[ -n "$OBSERVATION_PRIVATE_IP" ]]; then
    running "Chờ OTel Collector trên EC2 healthy (tối đa 10 phút)..."
    OTEL_TIMEOUT=600; OTEL_ELAPSED=0
    OTEL_HEALTH_URL="http://${OBSERVATION_PRIVATE_IP}:13133/"

    until curl -sf --max-time 3 "$OTEL_HEALTH_URL" > /dev/null 2>&1; do
      if [[ "$OTEL_ELAPSED" -ge "$OTEL_TIMEOUT" ]]; then
        warn "OTel Collector chưa healthy sau ${OTEL_TIMEOUT}s."
        warn "Kiểm tra userdata log trên EC2:"
        warn "  sudo cat /var/log/user-data.log"
        warn "Hoặc kiểm tra trạng thái containers:"
        warn "  sudo docker compose -f /opt/monitoring/docker-compose.yml ps"
        break
      fi
      warn "OTel Collector chưa ready — chờ 15s... (${OTEL_ELAPSED}s/${OTEL_TIMEOUT}s)"
      sleep 15; OTEL_ELAPSED=$((OTEL_ELAPSED + 15))
    done

    if curl -sf --max-time 3 "$OTEL_HEALTH_URL" > /dev/null 2>&1; then
      info "OTel Collector healthy ✓  ($OTEL_HEALTH_URL)"
    fi

    # Verify Grafana cũng healthy
    GRAFANA_HEALTH_URL="http://${OBSERVATION_PRIVATE_IP}:3000/api/health"
    if curl -sf --max-time 3 "$GRAFANA_HEALTH_URL" > /dev/null 2>&1; then
      info "Grafana healthy ✓  (http://${OBSERVATION_PUBLIC_IP:-$OBSERVATION_PRIVATE_IP}:3000)"
    else
      warn "Grafana chưa respond — có thể cần thêm thời gian"
    fi
  else
    warn "Không có IP EC2 — bỏ qua health check"
  fi

  info "Monitoring K8s resources deployed"
}

# -------------------------------------------------------
# BƯỚC 8: Xuất biến quan trọng
# -------------------------------------------------------
step "BƯỚC 8: Xuất biến ra file .env.output"

cat > "$OUTPUT_ENV_FILE" << ENVEOF
# ============================================================
# .env.output — Generated by setup.sh at $(date)
# ============================================================

# Nginx LoadBalancer endpoint (FRONTEND_ADDR cho k6 script)
NGINX_LB_ENDPOINT=${NGINX_LB:-<PENDING>}

# Observation EC2
OBSERVATION_PRIVATE_IP=${OBSERVATION_PRIVATE_IP:-<UNKNOWN>}
OBSERVATION_PUBLIC_IP=${OBSERVATION_PUBLIC_IP:-<UNKNOWN>}

# K6 EC2
K6_PRIVATE_IP=${K6_PRIVATE_IP:-<UNKNOWN>}
K6_PUBLIC_IP=${K6_PUBLIC_IP:-<UNKNOWN>}

# EKS
EKS_CLUSTER_NAME=${CLUSTER_NAME}
AWS_REGION=${REGION}

# Grafana + VictoriaMetrics
GRAFANA_URL=http://${OBSERVATION_PUBLIC_IP:-<UNKNOWN>}:3000
VICTORIAMETRICS_URL=http://${OBSERVATION_PUBLIC_IP:-<UNKNOWN>}:8428

# OTel Collector (nhận từ EKS agents)
OTEL_COLLECTOR_ENDPOINT=http://${OBSERVATION_PRIVATE_IP:-<UNKNOWN>}:4317

# Node assignments
GATEWAY_NODE=${GATEWAY_NODE:-<UNKNOWN>}
SERVICE_A_NODE=${SERVICE_A_NODE:-<UNKNOWN>}
SERVICE_B_NODE=${SERVICE_B_NODE:-<UNKNOWN>}
ENVEOF

info ".env.output ghi tại: $OUTPUT_ENV_FILE"

# -------------------------------------------------------
# Tóm tắt
# -------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════"
echo -e "  ✅  SETUP HOÀN THÀNH"
echo -e "══════════════════════════════════════════════${NC}"
echo ""
