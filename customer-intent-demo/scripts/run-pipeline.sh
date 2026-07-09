#!/usr/bin/env bash
# Upload do pipeline Banking77 no KFP e disparo de um PipelineRun.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-${HOME}/openshift-install-aws/auth/kubeconfig}"
export KUBECONFIG
NS="${NAMESPACE:-customer-intent-demo}"
RUN_NAME="${RUN_NAME:-banking77-kfp-$(date +%Y%m%d-%H%M%S)}"
KFP_HOST="${KFP_HOST:-https://$(oc get route ds-pipeline-dspa -n "${NS}" -o jsonpath='{.spec.host}')}"

echo "==> Compilando pipeline"
"${ROOT}/pipelines/.venv/bin/python" "${ROOT}/pipelines/compile_pipeline.py"

echo "==> Upload + run via KFP SDK (${KFP_HOST})"
"${ROOT}/pipelines/.venv/bin/python" "${ROOT}/scripts/run_pipeline.py" \
  --namespace "${NS}" \
  --host "${KFP_HOST}" \
  --pipeline-yaml "${ROOT}/pipelines/banking77-customer-intent-pipeline.yaml" \
  --run-name "${RUN_NAME}" \
  --service-account customer-intent-pipeline \
  "$@"
