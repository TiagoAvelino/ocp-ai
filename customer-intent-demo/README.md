# Customer Intent Classification (Banking77 MVP)

Solução de demonstração no OpenShift AI para classificar solicitações bancárias, comparar modelos no MLflow, registrar a versão aprovada e publicar inferência com roteamento empresarial via Quarkus.

## Arquitetura

```
Banking77 → Workbench PyTorch → MLflow + MinIO S3 → Model Registry
                                      ↓
                         Inferência FastAPI (DistilBERT)
                                      ↓
                              Backend Quarkus
                                      ↓
                           Filas empresariais / revisão humana
```

## Estrutura do repositório

```
customer-intent-demo/
├── config/                 # 12 intenções + filas + critérios de aprovação
├── training/               # prepare, baseline, DistilBERT, avaliação, registro
├── inference/              # FastAPI + Dockerfile
├── quarkus-backend/        # camada de negócio
├── openshift/              # manifests Kubernetes/OpenShift
├── scripts/                # install.sh, build-images.sh
├── pipelines/              # Kubeflow pipeline (contraste MLOps vs manual)
└── demo/                   # front-end HTML simples
└── demo-electron/          # UI Electron (apresentação ao vivo)
```

## Treino manual vs Pipeline (apresentação)

| Abordagem | Como executar | O que mostrar ao cliente |
|-----------|---------------|--------------------------|
| **Manual** | Workbench → `python training/run_experiments.py` | Exploração, notebooks, controle interativo |
| **Pipeline** | Dashboard → Pipelines → Import → Create run | DAG, reprodutibilidade, etapas paralelas, auditoria |

Importar pipeline:

```bash
./scripts/upload-pipeline.sh
# Dashboard → Projects → customer-intent-demo → Pipelines → Import
# Arquivo: pipelines/banking77-customer-intent-pipeline.yaml
```

Detalhes: [`pipelines/README.md`](pipelines/README.md)

## Pré-requisitos no cluster

- OpenShift AI 3.4 com `workbenches`, `mlflowoperator`, `modelregistry`, `kserve`
- MLflow CR aplicado (`openshift-ai/mlflow.yaml`)
- MinIO no namespace `minio`
- GPU NVIDIA L4 (recomendado para DistilBERT)

Verificação:

```bash
export KUBECONFIG=~/openshift-install-aws/auth/kubeconfig
oc get datasciencecluster -o yaml
```

## Deploy inicial

```bash
chmod +x scripts/install.sh scripts/build-images.sh
./scripts/install.sh
```

No dashboard OpenShift AI:

1. **Projects** → `customer-intent-demo`
2. **Settings** → Model registry → criar `enterprise-demo-registry` (se ainda não existir)
3. Abrir workbench `banking77-training`

## Treinamento no workbench

Copie este diretório para `/opt/app-root/src/customer-intent-demo` e execute:

```bash
cd customer-intent-demo
python -m pip install -r training/requirements.txt "mlflow[kubernetes]>=3.11"
export MLFLOW_TRACKING_AUTH=kubernetes-namespaced
export HF_HOME=/opt/app-root/src/model-cache
export TRANSFORMERS_CACHE=/opt/app-root/src/model-cache

python training/prepare_dataset.py --upload-s3
python training/run_experiments.py
python training/evaluate_and_select.py
```

Experimentos registrados no MLflow:

| Run | Modelo |
|-----|--------|
| `baseline-tfidf-logistic-regression` | TF-IDF + Logistic Regression |
| `distilbert-lr-2e-5-epochs-2` | DistilBERT conservador |
| `distilbert-lr-5e-5-epochs-3` | DistilBERT intermediário |
| `distilbert-lr-1e-4-epochs-3` | DistilBERT agressivo |

## Seleção e registro do modelo

Revise `reports/model-selection.json` e registre o run vencedor:

```bash
python training/register_model.py \
  --run-id <RUN_ID> \
  --model-dir artifacts/approved-model \
  --stage Approved
```

Envie o diretório aprovado para o S3:

```
s3://customer-intent-demo/models/customer-intent/approved/
```

## Publicação do endpoint

```bash
./scripts/build-images.sh
oc apply -f openshift/08-inference-deployment.yaml
oc apply -f openshift/09-inference-service-route.yaml
oc apply -f openshift/12-quarkus-backend.yaml
```

### Inferência (interno)

```bash
curl -s -X POST http://customer-intent-inference.customer-intent-demo.svc:8080/predict \
  -H 'Content-Type: application/json' \
  -d '{"text":"My transfer is still pending"}'
```

### Demo ao vivo

**No cluster (recomendado para apresentação):**

```
https://customer-intent-demo-ui-customer-intent-demo.apps.tiago-cluster.sandbox897.opentlc.com
```

Deploy:

```bash
oc apply -f openshift/15-demo-ui.yaml
oc start-build customer-intent-demo-ui \
  --from-dir=customer-intent-demo/demo-electron \
  -n customer-intent-demo --wait
```

**Desktop (Electron, desenvolvimento local):**

```bash
cd demo-electron
npm install
npm start
```

```bash
curl -s -X POST https://<route-backend>/api/v1/routing \
  -H 'Content-Type: application/json' \
  -d '{"text":"My transfer is still pending","correlationId":"demo-1"}'
```

Resposta esperada:

```json
{
  "correlationId": "demo-1",
  "predictedIntent": "pending_transfer",
  "department": "transfers-support",
  "decision": "AUTO_ROUTE",
  "modelVersion": "1.0.0",
  "queue": "transfers-support-queue"
}
```

## Regra empresarial

- `confidence >= 0.80` → `AUTO_ROUTE` para fila do departamento
- `confidence < 0.80` → `HUMAN_REVIEW`
- Timeout/erro do modelo → fallback para revisão humana

Thresholds avaliados na validação: `0.70`, `0.80`, `0.90`.

## 12 intenções MVP

| Departamento | Intenções |
|--------------|-----------|
| Cards Support | card_arrival, card_not_working, lost_or_stolen_card, card_payment_not_recognised |
| Transfers Support | pending_transfer, failed_transfer, beneficiary_not_allowed, transfer_not_received_by_recipient |
| Security and Identity | passcode_forgotten, unable_to_verify_identity |
| ATM Support | cash_withdrawal_not_recognised, wrong_amount_of_cash_received |

## Observabilidade

- Inferência: `/metrics` (Prometheus)
- Quarkus: `/metrics`, `/health`

## KServe (opcional)

Após validar o Deployment MVP:

```bash
oc apply -f openshift/10-kserve-servingruntime.yaml
```

## AI Pipelines (Kubeflow)

Pipeline compilado e pronto para import:

```bash
./scripts/upload-pipeline.sh
oc apply -f openshift/14-pipeline-rbac.yaml
```

DAG: `prepare → baseline + 3× DistilBERT (paralelo) → evaluate → publish`

Veja [`pipelines/README.md`](pipelines/README.md) para roteiro manual vs pipeline.

## Licença dos dados

Dataset [PolyAI/banking77](https://huggingface.co/datasets/PolyAI/banking77) sob **CC BY 4.0**.
