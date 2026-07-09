#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-${HOME}/openshift-install-aws/auth/kubeconfig}"
export KUBECONFIG
NS="${NAMESPACE:-customer-intent-demo}"

echo "==> Compilando pipeline Kubeflow"
python3 "${ROOT}/pipelines/compile_pipeline.py"

echo "==> RBAC do pipeline"
oc apply -f "${ROOT}/openshift/14-pipeline-rbac.yaml"

echo
echo "Para executar automaticamente (upload + run):"
echo "  ${ROOT}/scripts/run-pipeline.sh"
echo
echo "Import manual no OpenShift AI:"
echo "  Dashboard → Projects → ${NS} → Pipelines → Import pipeline"
echo "  Arquivo: ${ROOT}/pipelines/banking77-customer-intent-pipeline.yaml"
echo
echo "Ao criar um Pipeline run, use:"
echo "  Service account: customer-intent-pipeline"
echo "  PVC montado automaticamente: banking77-training"
echo
echo "Alternativa CLI (requer kfp instalado e token do pipeline server):"
echo "  pip install kfp==2.16.0"
echo "  # Configure KFP_ENDPOINT apontando ao pipeline server do projeto"
