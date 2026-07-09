#!/usr/bin/env bash
# Deploy GPU operators + KServe deps (NFD, NVIDIA, Serverless, Service Mesh 3)
# Usage:
#   export KUBECONFIG=/path/to/kubeconfig
#   ./ansible/scripts/deploy-gpu-stack.sh
#
# Optional env vars:
#   SKIP_HARDWARE_PROFILE=1     # skip nvidia-l4-profile (default if g6 profile exists)
#   GPU_NODE_LABEL_MANUAL=1     # force manual nvidia.com/gpu.present label
#   ANSIBLE_TAGS="nfd,nvidia"   # run only specific ansible tags

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
PLAYBOOK="${ANSIBLE_DIR}/playbook.yaml"

: "${KUBECONFIG:=/home/tavelino/openshift-install-aws/auth/kubeconfig}"
export KUBECONFIG

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

die() { err "$*"; exit 1; }

wait_for() {
  local desc="$1"
  shift
  local retries="${1:-60}"
  shift
  local delay="${1:-10}"
  shift
  log "Aguardando: ${desc}..."
  local i
  for ((i = 1; i <= retries; i++)); do
    if "$@" >/dev/null 2>&1; then
      log "OK: ${desc}"
      return 0
    fi
    sleep "${delay}"
  done
  die "Timeout: ${desc}"
}

run_ansible() {
  local tags="$1"
  log "ansible-playbook --tags ${tags}"
  ansible-playbook "${PLAYBOOK}" --tags "${tags}"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
log "KUBECONFIG=${KUBECONFIG}"
command -v oc >/dev/null || die "oc não encontrado no PATH"
command -v ansible-playbook >/dev/null || die "ansible-playbook não encontrado. Instale: dnf install ansible-core"
oc whoami >/dev/null || die "Não logado no cluster. Execute: oc login"
oc cluster-info >/dev/null

if ! ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core; then
  log "Instalando collections Ansible..."
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yaml"
fi

# ---------------------------------------------------------------------------
# Step 1: NFD Operator
# ---------------------------------------------------------------------------
log "========== Step 1/5: NFD Operator =========="
if [[ -n "${ANSIBLE_TAGS:-}" ]]; then
  run_ansible "${ANSIBLE_TAGS}"
else
  run_ansible "prerequisites,nfd"
fi

wait_for "NFD CSV Succeeded" 60 10 \
  oc get csv -n openshift-nfd -o jsonpath='{.items[0].status.phase}' | grep -q Succeeded

wait_for "NFD master pod Running" 30 10 \
  oc get pods -n openshift-nfd -l app=nfd-master --field-selector=status.phase=Running -o name

# ---------------------------------------------------------------------------
# Step 2: NVIDIA GPU Operator
# ---------------------------------------------------------------------------
log "========== Step 2/5: NVIDIA GPU Operator =========="
if [[ -z "${ANSIBLE_TAGS:-}" ]]; then
  run_ansible "nvidia"
fi

wait_for "NVIDIA GPU CSV Succeeded" 90 15 \
  bash -c '[[ "$(oc get csv -n nvidia-gpu-operator -o jsonpath="{.items[0].status.phase}" 2>/dev/null)" == "Succeeded" ]]'

wait_for "ClusterPolicy gpu-cluster-policy" 30 10 \
  oc get clusterpolicy gpu-cluster-policy

log "Aguardando pods do GPU operator (driver + device-plugin podem levar 10-20 min)..."
wait_for "GPU operator daemonset pods" 120 15 \
  bash -c '[[ "$(oc get pods -n nvidia-gpu-operator --no-headers 2>/dev/null | grep -c Running || true)" -ge 1 ]]'

# ---------------------------------------------------------------------------
# Step 3: Label GPU nodes (se GFD não aplicou automaticamente)
# ---------------------------------------------------------------------------
log "========== Step 3/5: Labels GPU nos nós =========="

GPU_INSTANCE_REGEX='^(g[0-9]|g4dn|g5|g6|p[0-9]|p3|p4|inf1)'

while IFS= read -r node; do
  [[ -z "${node}" ]] && continue
  instance_type="$(oc get node "${node}" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}')"
  has_label="$(oc get node "${node}" -o jsonpath='{.metadata.labels.nvidia\.com/gpu\.present}' 2>/dev/null || true)"

  if [[ "${instance_type}" =~ ${GPU_INSTANCE_REGEX} ]] || [[ "${GPU_NODE_LABEL_MANUAL:-}" == "1" ]]; then
    if [[ "${has_label}" != "true" ]]; then
      warn "Aplicando label nvidia.com/gpu.present=true em ${node} (${instance_type})"
      oc label node "${node}" nvidia.com/gpu.present=true --overwrite
    else
      log "Nó ${node} já tem nvidia.com/gpu.present=true"
    fi
  fi
done < <(oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# ---------------------------------------------------------------------------
# Step 4: Serverless + Service Mesh 3 (KServe deps)
# ---------------------------------------------------------------------------
log "========== Step 4/5: Serverless + Service Mesh 3 =========="
if [[ -z "${ANSIBLE_TAGS:-}" ]]; then
  run_ansible "serverless,servicemesh3"
fi

wait_for "Serverless CSV Succeeded" 60 10 \
  bash -c '[[ "$(oc get csv -n openshift-serverless -o jsonpath="{.items[0].status.phase}" 2>/dev/null)" == "Succeeded" ]]'

wait_for "Service Mesh 3 CSV Succeeded" 60 10 \
  bash -c 'oc get csv -n openshift-operators 2>/dev/null | grep -q servicemeshoperator3'

# ---------------------------------------------------------------------------
# Step 5: Hardware Profile (opcional — pule se já tiver g6-12xlarge-4gpu-profile)
# ---------------------------------------------------------------------------
log "========== Step 5/5: Hardware Profile =========="
if [[ "${SKIP_HARDWARE_PROFILE:-}" == "1" ]] || oc get hardwareprofile g6-12xlarge-4gpu-profile -n redhat-ods-applications >/dev/null 2>&1; then
  warn "Pulando nvidia-l4-profile (g6-12xlarge-4gpu-profile já existe ou SKIP_HARDWARE_PROFILE=1)"
else
  run_ansible "hardware-profile"
fi

# ---------------------------------------------------------------------------
# Validação final
# ---------------------------------------------------------------------------
log "========== Validação =========="
echo ""
echo "--- Operators ---"
oc get csv -n openshift-nfd 2>/dev/null | head -3 || true
oc get csv -n nvidia-gpu-operator 2>/dev/null | head -3 || true
oc get csv -n openshift-serverless 2>/dev/null | head -3 || true
oc get csv -n openshift-operators 2>/dev/null | grep servicemesh || true

echo ""
echo "--- GPU nos nós ---"
oc get nodes -o custom-columns=\
NAME:.metadata.name,\
INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type,\
GPU_PRESENT:.metadata.labels.nvidia\.com/gpu\.present,\
GPU_ALLOC:.status.allocatable.nvidia\\.com/gpu,\
TAINTS:.spec.taints

echo ""
echo "--- ClusterPolicy ---"
oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}{"\n"}' 2>/dev/null || warn "ClusterPolicy ainda não reportou status"

echo ""
GPU_ALLOC="$(oc get nodes -o json | python3 -c "
import json,sys
data=json.load(sys.stdin)
vals=[n['status'].get('allocatable',{}).get('nvidia.com/gpu','') for n in data['items']]
print(','.join(v for v in vals if v))
" 2>/dev/null || true)"

if [[ -n "${GPU_ALLOC}" ]]; then
  log "GPU allocatable detectada: ${GPU_ALLOC}"
  log "Stack GPU instalado com sucesso."
else
  warn "nvidia.com/gpu ainda não aparece como allocatable."
  warn "Possíveis causas:"
  warn "  - driver ainda instalando (aguarde 10-20 min e rode a validação de novo)"
  warn "  - GPU está no master com taint dedicated=gpu (workloads precisam de toleration)"
  warn "  - worker é m6i (sem GPU) — crie um MachineSet GPU se necessário"
  echo ""
  echo "Revalidar:"
  echo "  oc get pods -n nvidia-gpu-operator"
  echo "  oc describe node <gpu-node> | grep -A10 Allocatable"
fi

echo ""
log "Concluído."
