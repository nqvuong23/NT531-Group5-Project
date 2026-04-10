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
#   9. Lệnh SCP copy các file script và thư mục lên các EC2
#   10. Tự động SSH tới 2 EC2 rồi chạy file script tải và cấu hình tự động
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

OBSERVATION_CONFIG_DIR="${PROJECT_ROOT}/observation_ec2_config"
K6_CONFIG_DIR="${PROJECT_ROOT}/k6_ec2_config"
K6_SCRIPT_DIR="${PROJECT_ROOT}/script"

SSH_KEY_DIR="${TERRAFORM_DIR}/keypair"
REMOTE_DESTINATION_DIR="/home/ubuntu/"
REMOTE_OBSERVATION_SETUP_FILE="${REMOTE_DESTINATION_DIR}/observation_ec2_config/observation_ec2_setup.sh"
REMOTE_K6_SETUP_FILE="${REMOTE_DESTINATION_DIR}/k6_ec2_config/k6_ec2_setup.sh"

CLUSTER_NAME="${CLUSTER_NAME:-NT531-Project-Group5-dev-eks}"
REGION="${AWS_REGION:-ap-southeast-1}"
PROFILE="${AWS_PROFILE:-dev}"

OUTPUT_ENV_FILE="${PROJECT_ROOT}/.env.output"
K6_ENV_FILE="${K6_CONFIG_DIR}/sources/.env"

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

OBSERVATION_INSTANCE_ID=$(terraform output -raw observation_instance_id 2>/dev/null || echo "")
OBSERVATION_PRIVATE_IP=$(terraform output -raw observation_private_ip 2>/dev/null || echo "")
OBSERVATION_PUBLIC_IP=$(terraform output -raw observation_public_ip 2>/dev/null || echo "")

K6_INSTANCE_ID=$(terraform output -raw k6_instance_id 2>/dev/null || echo "")
K6_PRIVATE_IP=$(terraform output -raw k6_private_ip 2>/dev/null || echo "")
K6_PUBLIC_IP=$(terraform output -raw k6_public_ip 2>/dev/null || echo "")

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

if [[ -z "$OBSERVATION_INSTANCE_ID" ]]; then
  warn "Không đọc được OBSERVATION_INSTANCE_ID. Nhập (hoặc Enter bỏ qua):"
  read -r OBSERVATION_INSTANCE_ID || true
fi

if [[ -z "$K6_PRIVATE_IP" ]]; then
  warn "Không đọc được k6_private_ip từ terraform output."
  warn "Nhập Private IP của EC2 monitoring (bắt buộc cho ConfigMap patch):"
  read -r K6_PRIVATE_IP || true
fi

if [[ -z "$K6_PUBLIC_IP" ]]; then
  warn "Không đọc được k6_public_ip. Nhập (hoặc Enter bỏ qua):"
  read -r K6_PUBLIC_IP || true
fi

if [[ -z "$K6_INSTANCE_ID" ]]; then
  warn "Không đọc được K6_INSTANCE_ID. Nhập (hoặc Enter bỏ qua):"
  read -r K6_INSTANCE_ID || true
fi

info "EKS Cluster Name:           ${CLUSTER_NAME}"
info "Observation Private IP:     ${OBSERVATION_PRIVATE_IP:-N/A}"
info "Observation Public IP:      ${OBSERVATION_PUBLIC_IP:-N/A}"
info "Observation Instance ID:    ${OBSERVATION_INSTANCE_ID:-N/A}"
info "K6 Private IP:              ${K6_PRIVATE_IP:-N/A}"
info "K6 Public IP:               ${K6_PUBLIC_IP:-N/A}"
info "K6 Instance ID:             ${K6_INSTANCE_ID:-N/A}"

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
    running "Patching monitoring-endpoints ConfigMap: ${OBSERVATION_PRIVATE_IP}:4317"
    kubectl -n monitoring patch configmap monitoring-endpoints \
      --type merge \
      -p "{\"data\":{\"otel_collector_endpoint\":\"${OBSERVATION_PRIVATE_IP}:4317\"}}"
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
}

# -------------------------------------------------------
# BƯỚC 8: Xuất biến quan trọng
# -------------------------------------------------------
step "BƯỚC 8: Xuất biến ra file .env.output và file .env"

cat > "$OUTPUT_ENV_FILE" << ENVEOF
# ============================================================
# .env.output — Generated by setup.sh at $(date)
# ============================================================

# Nginx LoadBalancer endpoint (FRONTEND_ADDR cho k6 script)
NGINX_LB_ENDPOINT=${NGINX_LB:-<PENDING>}

# Observation EC2
OBSERVATION_INSTANCE_ID=${OBSERVATION_INSTANCE_ID:-<UNKNOWN>}
OBSERVATION_PRIVATE_IP=${OBSERVATION_PRIVATE_IP:-<UNKNOWN>}
OBSERVATION_PUBLIC_IP=${OBSERVATION_PUBLIC_IP:-<UNKNOWN>}

# K6 EC2
K6_INSTANCE_ID=${K6_INSTANCE_ID:-<UNKNOWN>}
K6_PRIVATE_IP=${K6_PRIVATE_IP:-<UNKNOWN>}
K6_PUBLIC_IP=${K6_PUBLIC_IP:-<UNKNOWN>}

# SSH to EC2 command
SSH_COMMAND_TO_OBSERVATION_EC2=ssh -i ${SSH_KEY_DIR}/key -o StrictHostKeyChecking=no ubuntu@${OBSERVATION_PUBLIC_IP}
SSH_COMMAND_TO_K6_EC2=ssh -i ${SSH_KEY_DIR}/key -o StrictHostKeyChecking=no ubuntu@${K6_PUBLIC_IP}

# EKS
EKS_CLUSTER_NAME=${CLUSTER_NAME}
AWS_REGION=${REGION}

# Grafana + VictoriaMetrics
GRAFANA_URL=http://${OBSERVATION_PUBLIC_IP:-<UNKNOWN>}:3000
VICTORIAMETRICS_URL=http://${OBSERVATION_PUBLIC_IP:-<UNKNOWN>}:8428

# OTel Collector (nhận từ EKS agents)
OTEL_COLLECTOR_ENDPOINT=${OBSERVATION_PRIVATE_IP:-<UNKNOWN>}:4317

# Node assignments
GATEWAY_NODE=${GATEWAY_NODE:-<UNKNOWN>}
SERVICE_A_NODE=${SERVICE_A_NODE:-<UNKNOWN>}
SERVICE_B_NODE=${SERVICE_B_NODE:-<UNKNOWN>}
ENVEOF

info ".env.output ghi tại: $OUTPUT_ENV_FILE"

cat > "$K6_ENV_FILE" << ENVEOF
# OTel Collector Endpoint (IP Private of Observation EC2) 
OTEL_COLLECTOR_ENDPOINT=${OBSERVATION_PRIVATE_IP:-<UNKNOWN>}:4317

# Endpoint ĐÚNG cho k6 trỏ về Agent cục bộ (gRPC)
K6_OTEL_GRPC_EXPORTER_ENDPOINT=localhost:4317

# Các biến bổ sung để k6 chạy mượt hơn
K6_OTEL_GRPC_EXPORTER_INSECURE=true
K6_OTEL_METRIC_PREFIX=k6

# Lệnh mỗi khi chạy k6 script
K6_RUN_COMMAND="k6 run --out opentelemetry <script file name>"
ENVEOF

info ".env.output ghi tại: $K6_ENV_FILE"

# --------------------------------------------------------------------
# BƯỚC 9: Lệnh SCP copy các file script và thư mục để đưa lên các EC2
# --------------------------------------------------------------------
step "BƯỚC 9: Lệnh SCP COPY các file script và thư mục lên các EC2"

info "Dừng 90 giây để EC2 init hoàn tất"
sleep 90

running "Bắt đầu chạy lệnh SCP ...."

chmod 700 $SSH_KEY_DIR
chmod 600 "${SSH_KEY_DIR}/key"

scp -i "${SSH_KEY_DIR}/key" -o StrictHostKeyChecking=no -r "${OBSERVATION_CONFIG_DIR}" "ubuntu@${OBSERVATION_PUBLIC_IP}:${REMOTE_DESTINATION_DIR}"
scp -i "${SSH_KEY_DIR}/key" -o StrictHostKeyChecking=no -r "${K6_CONFIG_DIR}" "ubuntu@${K6_PUBLIC_IP}:${REMOTE_DESTINATION_DIR}"
scp -i "${SSH_KEY_DIR}/key" -o StrictHostKeyChecking=no -r "${K6_SCRIPT_DIR}" "ubuntu@${K6_PUBLIC_IP}:${REMOTE_DESTINATION_DIR}"

info "Đã COPY các file script và thư mục lên các EC2 thành công"

# -----------------------------------------------------------------------
# BƯỚC 10: Tự động SSH tới 2 EC2 và tự động chạy file scrip để cấu hình
# -----------------------------------------------------------------------
step "BƯỚC 10: Tự động SSH tới 2 EC2 và tự động chạy file scrip để cấu hình"

running "Bắt đầu SSH tới EC2 K6 ...."
ssh -i "${SSH_KEY_DIR}/key" -o StrictHostKeyChecking=no "ubuntu@${k6_PUBLIC_IP}" << EOF
  chmod +x $REMOTE_K6_SETUP_FILE
  sudo bash $REMOTE_K6_SETUP_FILE
EOF
info "Đã SSH tới EC2 K6 và chạy file setup thành công"

running "Bắt đầu SSH tới EC2 Observation ...."
ssh -i "${SSH_KEY_DIR}/key" -o StrictHostKeyChecking=no "ubuntu@${OBSERVATION_PUBLIC_IP}" << EOF
  chmod +x $REMOTE_OBSERVATION_SETUP_FILE
  sudo bash $REMOTE_OBSERVATION_SETUP_FILE
EOF
info "Đã SSH tới EC2 Observation và chạy file setup thành công"

# -------------------------------------------------------
# Tóm tắt
# -------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════"
echo -e "  ✅  SETUP HOÀN THÀNH"
echo -e "══════════════════════════════════════════════${NC}"
echo ""
