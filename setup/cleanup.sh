#!/usr/bin/env bash
# ============================================================
# cleanup.sh — Master Cleanup Script
# Dọn dẹp toàn bộ tài nguyên được tạo bởi setup.sh.
#
# Thứ tự thực hiện (ngược với setup.sh):
#   1. Kiểm tra prerequisites
#   2. Kiểm tra AWS credentials
#   3. Load biến từ .env.output (nếu có)
#   4. Cập nhật kubeconfig để kubectl còn hoạt động
#   5. [K8s] Xóa monitoring namespace (DaemonSets + ConfigMaps)
#   6. [K8s] Xóa microservice manifests (Deployments, Services, ...)
#   7. [K8s] Xóa nginx-gateway + LoadBalancer Service
#      ⚠ Chờ AWS NLB bị xóa hoàn toàn trước khi terraform destroy
#         (nếu còn NLB, terraform destroy sẽ bị treo ở VPC/subnet)
#   8. [K8s] Xóa node labels & taints
#   9. terraform destroy
#  10. Xóa file .env.output + kubeconfig context
#
# CÁCH DÙNG:
#   chmod +x setup/cleanup.sh
#   ./setup/cleanup.sh
#
# FLAGS:
#   --force     Bỏ qua bước xác nhận "Bạn có chắc chắn?"
#   --skip-k8s  Bỏ qua xóa K8s resources (dùng khi cluster đã bị xóa)
# ============================================================

set -euo pipefail

# -------------------------------------------------------
# Parse flags
# -------------------------------------------------------
FORCE=false
SKIP_K8S=false
for arg in "$@"; do
  case "$arg" in
    --force)    FORCE=true ;;
    --skip-k8s) SKIP_K8S=true ;;
  esac
done

# -------------------------------------------------------
# Constants & Paths (mirror setup.sh)
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
# Colors (giống setup.sh)
# -------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

step()    { echo -e "\n${BOLD}${BLUE}══════ $* ══════${NC}"; }
info()    { echo -e "  ${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $*"; }
error()   { echo -e "  ${RED}[✗]${NC} $*" >&2; exit 1; }
running() { echo -e "  ${CYAN}[→]${NC} $*"; }
skipped() { echo -e "  ${YELLOW}[-]${NC} $* (skipped)"; }

# Helper: kubectl delete với --ignore-not-found để không fail
k8s_delete() {
  kubectl delete "$@" --ignore-not-found=true 2>/dev/null || true
}

# -------------------------------------------------------
# BƯỚC 1: Kiểm tra prerequisites
# -------------------------------------------------------
step "BƯỚC 1: Kiểm tra prerequisites"

MISSING_TOOLS=()
for tool in terraform kubectl aws jq; do
  if command -v "$tool" &>/dev/null; then
    info "$tool: OK"
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
elif aws sts get-caller-identity --output json 2>/dev/null \
     | jq -r '.Arn' > /dev/null 2>&1; then
  CALLER_ARN=$(aws sts get-caller-identity --output json 2>/dev/null \
    | jq -r '.Arn')
  PROFILE=""
  info "Authenticated via environment vars: $CALLER_ARN"
else
  error "Không có AWS credentials hợp lệ. Chạy 'aws configure' hoặc set AWS env vars."
fi

PROFILE_ARG=""
[[ -n "$PROFILE" ]] && PROFILE_ARG="--profile $PROFILE"

# -------------------------------------------------------
# BƯỚC 3: Load .env.output (nếu có)
# -------------------------------------------------------
step "BƯỚC 3: Load biến từ .env.output"

if [[ -f "$OUTPUT_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  set -o allexport
  # Chỉ load các dòng KEY=VALUE, bỏ comment
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    # Trim whitespace
    key="${key// /}"
    value="${value// /}"
    export "${key}=${value}" 2>/dev/null || true
  done < <(grep -v '^\s*#' "$OUTPUT_ENV_FILE" | grep '=')
  set +o allexport

  # Override các biến cần thiết từ .env.output
  [[ -n "${EKS_CLUSTER_NAME:-}" ]] && CLUSTER_NAME="$EKS_CLUSTER_NAME"
  [[ -n "${AWS_REGION:-}"       ]] && REGION="$AWS_REGION"

  info ".env.output loaded"
  info "  Cluster:  $CLUSTER_NAME"
  info "  Region:   $REGION"
else
  warn ".env.output không tìm thấy — dùng default values"
  warn "  Cluster:  $CLUSTER_NAME"
  warn "  Region:   $REGION"
fi

# -------------------------------------------------------
# Xác nhận trước khi xóa (trừ khi --force)
# -------------------------------------------------------
if [[ "$FORCE" == false ]]; then
  echo ""
  echo -e "${BOLD}${RED}  ⚠️  CẢNH BÁO: Thao tác này sẽ XÓA TOÀN BỘ tài nguyên AWS!${NC}"
  echo -e "  Cluster:  ${BOLD}${CLUSTER_NAME}${NC}"
  echo -e "  Region:   ${BOLD}${REGION}${NC}"
  echo ""
  # read -r -p "  Bạn có chắc chắn muốn xóa? Gõ 'yes' để xác nhận: " CONFIRM
  # [[ "$CONFIRM" != "yes" ]] && { echo "  Đã hủy."; exit 0; }
fi

# -------------------------------------------------------
# BƯỚC 4: Cập nhật kubeconfig
# (Cần kubeconfig còn valid để xóa K8s resources trước
#  khi terraform destroy xóa cluster)
# -------------------------------------------------------
step "BƯỚC 4: Cập nhật kubeconfig"

K8S_AVAILABLE=false
if aws eks update-kubeconfig \
     --region "$REGION" \
     --name   "$CLUSTER_NAME" \
     ${PROFILE_ARG} 2>/dev/null; then
  # Kiểm tra cluster còn accessible không
  if kubectl get nodes --request-timeout=10s &>/dev/null 2>&1; then
    K8S_AVAILABLE=true
    info "kubectl OK — cluster accessible"
  else
    warn "kubectl không thể kết nối cluster — có thể cluster đã bị xóa"
  fi
else
  warn "Không thể update kubeconfig — cluster có thể đã không tồn tại"
fi

if [[ "$SKIP_K8S" == true ]]; then
  K8S_AVAILABLE=false
  warn "--skip-k8s flag: bỏ qua toàn bộ kubectl operations"
fi

# -------------------------------------------------------
# BƯỚC 5: Xóa monitoring K8s resources
# (DaemonSets: otel-agent, node-exporter + namespace monitoring)
# -------------------------------------------------------
step "BƯỚC 5: Xóa monitoring K8s resources"

if [[ "$K8S_AVAILABLE" == true ]]; then

  if [[ -f "${MONITORING_K8S_DIR}/node-exporter-daemonset.yaml" ]]; then
    running "kubectl delete -f node-exporter-daemonset.yaml..."
    kubectl delete -f "${MICROSERVICES_K8S_DIR}/node-exporter-daemonset.yaml" \
      --ignore-not-found=true 2>/dev/null || true
    info "node-exporter-daemonset.yaml deleted"
  else
    warn "Không tìm thấy node-exporter-daemonset.yaml — bỏ qua"
  fi

  if [[ -f "${MONITORING_K8S_DIR}/otel-agent-daemonset.yaml" ]]; then
    running "kubectl delete -f otel-agent-daemonset.yaml..."
    kubectl delete -f "${MICROSERVICES_K8S_DIR}/otel-agent-daemonset.yaml" \
      --ignore-not-found=true 2>/dev/null || true
    info "otel-agent-daemonset.yaml deleted"
  else
    warn "Không tìm thấy otel-agent-daemonset.yaml — bỏ qua"
  fi

  if [[ -f "${MONITORING_K8S_DIR}/monitoring-namespace.yaml" ]]; then
    running "kubectl delete -f monitoring-namespace.yaml..."
    kubectl delete -f "${MICROSERVICES_K8S_DIR}/monitoring-namespace.yaml" \
      --ignore-not-found=true 2>/dev/null || true
    info "monitoring-namespace.yaml deleted"
  else
    warn "Không tìm thấy monitoring-namespace.yaml — bỏ qua"
  fi

else
  skipped "monitoring K8s resources"
fi

# -------------------------------------------------------
# BƯỚC 6: Xóa microservice manifests
# (Deployments, Services, ServiceAccounts, ConfigMaps
#  từ kubernetes-manifests.yaml — namespace: default)
# -------------------------------------------------------
step "BƯỚC 6: Xóa microservice manifests"

if [[ "$K8S_AVAILABLE" == true ]]; then

  if [[ -f "${MICROSERVICES_K8S_DIR}/kubernetes-manifests.yaml" ]]; then
    running "kubectl delete -f kubernetes-manifests.yaml..."
    kubectl delete -f "${MICROSERVICES_K8S_DIR}/kubernetes-manifests.yaml" \
      --ignore-not-found=true 2>/dev/null || true
    info "kubernetes-manifests.yaml deleted"
  else
    warn "Không tìm thấy kubernetes-manifests.yaml — bỏ qua"
  fi

else
  skipped "microservice manifests"
fi

# -------------------------------------------------------
# BƯỚC 7: Xóa nginx-gateway + chờ AWS NLB bị xóa
#
# ⚠️  QUAN TRỌNG: Phải xóa LoadBalancer Service TRƯỚC khi
# terraform destroy. Nếu còn NLB tồn tại, terraform destroy
# sẽ bị treo khi xóa subnet/VPC vì AWS từ chối xóa VPC
# đang có load balancer attached.
#
# Flow:
#   kubectl delete svc nginx-gateway
#     → K8s Cloud Controller xóa AWS NLB
#     → Chờ NLB biến mất khỏi AWS (poll aws elbv2)
# -------------------------------------------------------
step "BƯỚC 7: Xóa nginx-gateway + chờ AWS NLB terminate"

if [[ "$K8S_AVAILABLE" == true ]]; then

  # Lấy hostname NLB trước khi xóa (cần để poll trạng thái)
  NLB_HOSTNAME=$(kubectl get svc nginx-gateway \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

  if [[ -f "${MICROSERVICES_K8S_DIR}/nginx-gateway.yaml" ]]; then
    running "kubectl delete -f nginx-gateway.yaml..."
    kubectl delete -f "${MICROSERVICES_K8S_DIR}/nginx-gateway.yaml" \
      --ignore-not-found=true 2>/dev/null || true
    info "nginx-gateway.yaml deleted"
  else
    # Fallback: xóa trực tiếp từng resource
    running "Xóa nginx-gateway resources trực tiếp..."
    k8s_delete deployment  nginx-gateway
    k8s_delete service     nginx-gateway
    k8s_delete configmap   nginx-config
  fi

  sleep 15

else
  skipped "nginx-gateway / NLB cleanup"
  warn "Nếu NLB vẫn còn tồn tại, terraform destroy có thể bị treo."
  warn "Kiểm tra thủ công: aws elbv2 describe-load-balancers --region $REGION"
fi

# -------------------------------------------------------
# BƯỚC 8: Xóa node labels & taints
# (Không bắt buộc vì nodes sẽ bị xóa bởi terraform,
#  nhưng giúp cluster sạch nếu cần dùng lại)
# -------------------------------------------------------
step "BƯỚC 8: Xóa node labels & taints"

if [[ "$K8S_AVAILABLE" == true ]]; then

  mapfile -t NODE_ARRAY < <(kubectl get nodes --no-headers \
    -o custom-columns="NAME:.metadata.name" 2>/dev/null | sort || true)

  if [[ ${#NODE_ARRAY[@]} -gt 0 ]]; then
    for node in "${NODE_ARRAY[@]}"; do
      running "Xóa label và taint trên node: $node"
      kubectl label node "$node" role- --overwrite 2>/dev/null || true
      kubectl taint node "$node" role- 2>/dev/null || true
    done
    info "Labels & taints đã xóa trên ${#NODE_ARRAY[@]} nodes"
  else
    warn "Không tìm thấy node nào — bỏ qua"
  fi

else
  skipped "node labels & taints"
fi

# -------------------------------------------------------
# BƯỚC 9: Terraform destroy
# -------------------------------------------------------
step "BƯỚC 9: Terraform destroy"

[[ ! -d "$TERRAFORM_DIR" ]] && error "Không tìm thấy $TERRAFORM_DIR"

cd "$TERRAFORM_DIR"

# Kiểm tra có terraform state không
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
  # Thử kiểm tra remote state nếu dùng S3 backend
  if terraform state list &>/dev/null 2>&1; then
    : # remote state OK
  else
    warn "Không tìm thấy terraform state — có thể infra đã bị xóa trước đó"
    warn "Bỏ qua terraform destroy"
    cd "$PROJECT_ROOT"
    # Vẫn tiếp tục để xóa file local
    # shellcheck disable=SC2209
    SKIP_TF_DESTROY=true
  fi
fi

SKIP_TF_DESTROY="${SKIP_TF_DESTROY:-false}"

if [[ "$SKIP_TF_DESTROY" == false ]]; then
  running "terraform destroy (auto-approve)..."
  running "⏳ Quá trình này thường mất 10-20 phút (EKS cluster deletion)..."

  terraform destroy -auto-approve

  info "Terraform destroy hoàn thành"
else
  skipped "terraform destroy (không có state)"
fi

cd "$PROJECT_ROOT"

# -------------------------------------------------------
# BƯỚC 10: Xóa file local được tạo bởi setup.sh
# -------------------------------------------------------
step "BƯỚC 10: Dọn dẹp file local"

# Xóa .env.output
if [[ -f "$OUTPUT_ENV_FILE" ]]; then
  rm -f "$OUTPUT_ENV_FILE"
  info "Đã xóa: $OUTPUT_ENV_FILE"
else
  skipped ".env.output (không tồn tại)"
fi

# Xóa kubeconfig context cho cluster này
running "Xóa kubeconfig context: $CLUSTER_NAME"
KUBE_CONTEXT="arn:aws:eks:${REGION}:$(aws sts get-caller-identity \
  --output text --query 'Account' ${PROFILE_ARG} 2>/dev/null \
  || echo 'unknown'):cluster/${CLUSTER_NAME}"

kubectl config delete-context "$KUBE_CONTEXT"  2>/dev/null && \
  info "Đã xóa context: $KUBE_CONTEXT" || \
  warn "Context không tồn tại hoặc đã xóa: $KUBE_CONTEXT"

kubectl config delete-cluster "$KUBE_CONTEXT"  2>/dev/null || true
kubectl config unset "users.${KUBE_CONTEXT}"   2>/dev/null || true

# -------------------------------------------------------
# Tóm tắt
# -------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════"
echo -e "  ✅  CLEANUP HOÀN THÀNH"
echo -e "══════════════════════════════════════════════${NC}"
echo ""
echo -e "  Các tài nguyên đã được dọn dẹp:"
echo -e "  ${GREEN}✓${NC}  K8s: monitoring namespace (otel-agent, node-exporter)"
echo -e "  ${GREEN}✓${NC}  K8s: microservice deployments + services (default namespace)"
echo -e "  ${GREEN}✓${NC}  K8s: nginx-gateway deployment + AWS NLB"
echo -e "  ${GREEN}✓${NC}  K8s: node labels & taints"
echo -e "  ${GREEN}✓${NC}  AWS: terraform destroy (EKS cluster, EC2, VPC, ...)"
echo -e "  ${GREEN}✓${NC}  Local: .env.output, kubeconfig context"
echo ""
echo -e "  ${YELLOW}Lưu ý:${NC} Kiểm tra AWS Console để đảm bảo không còn tài nguyên tính phí:"
echo -e "    - EC2 Instances"
echo -e "    - EKS Cluster"
echo -e "    - Load Balancers (EC2 → Load Balancers)"
echo -e "    - NAT Gateways (VPC → NAT Gateways)"
echo ""