#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-${HOME}/openshift-install-aws/auth/kubeconfig}"
export KUBECONFIG

echo "==> Criando bucket MinIO customer-intent-demo (se necessário)"
oc exec -n minio deploy/minio -- sh -c '
  mc alias set local http://127.0.0.1:9000 tempo supersecret 2>/dev/null || true
  mc mb --ignore-existing local/customer-intent-demo
' || echo "Aviso: crie o bucket manualmente no MinIO se o comando falhar."

echo "==> Aplicando manifests OpenShift"
for manifest in \
  "${ROOT}/openshift/01-namespace.yaml" \
  "${ROOT}/openshift/02-s3-connection-secret.yaml" \
  "${ROOT}/openshift/02b-mlflow-artifact-secret.yaml" \
  "${ROOT}/openshift/03-mlflow-config.yaml" \
  "${ROOT}/openshift/04-workbench-pvc.yaml" \
  "${ROOT}/openshift/05-workbench-sa-rbac.yaml" \
  "${ROOT}/openshift/06-workbench-notebook.yaml" \
  "${ROOT}/openshift/07-model-pvc.yaml" \
  "${ROOT}/openshift/16-hardware-profile.yaml"
do
  oc apply -f "${manifest}"
done

echo "==> RBAC pipeline Kubeflow"
oc apply -f "${ROOT}/openshift/14-pipeline-rbac.yaml"

echo "==> Compilar pipeline (YAML para import no dashboard)"
python3 "${ROOT}/pipelines/compile_pipeline.py"

echo "==> MLflow cluster-scoped (se ainda não existir)"
oc apply -f "${ROOT}/../openshift-ai/mlflow.yaml"

echo
echo "Próximos passos:"
echo "1. Copie este repositório para o PVC do workbench banking77-training"
echo "2. No workbench: pip install -r training/requirements.txt"
echo "3. Importe o pipeline: Pipelines → Import → pipelines/banking77-customer-intent-pipeline.yaml"
echo "4. Execute: python training/run_experiments.py  (manual) OU Create pipeline run (MLOps)"
echo "5. Registre o modelo: python training/register_model.py --run-id <RUN_ID>"
echo "5. Envie o modelo aprovado para s3://customer-intent-demo/models/customer-intent/approved/"
echo "6. Build/push das imagens inference e quarkus-backend"
echo "7. oc apply -f openshift/08-inference-deployment.yaml -f openshift/09-inference-service-route.yaml -f openshift/12-quarkus-backend.yaml"
