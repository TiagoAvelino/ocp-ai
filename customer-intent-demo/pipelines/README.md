# Pipeline Kubeflow — Customer Intent (Banking77)

Pipeline reproduzível para contrastar com o treino **manual** no workbench.

## Por que existem duas formas?

| | Manual (Workbench) | Pipeline (Kubeflow) |
|---|---|---|
| **Onde roda** | Terminal/notebook interativo | DAG orquestrado pelo OpenShift AI |
| **Reprodutibilidade** | Depende do operador | Idempotente, versionável, reexecutável |
| **Visibilidade** | Logs em arquivo | Grafo visual + status por etapa |
| **Paralelismo** | Sequencial (`run_experiments.py`) | 3 DistilBERT em paralelo após prep |
| **Governança** | Laboratório / exploração | MLOps / produção / auditoria |
| **Código** | `training/run_experiments.py` | `pipelines/banking77_training_pipeline.py` |

**Mensagem para clientes:** o mesmo código Python alimenta as duas abordagens; a diferença é **como** o OpenShift AI orquestra a execução.

## DAG do pipeline

```
1. Preparar dataset
        │
        ├── 2. Baseline TF-IDF (CPU)
        │
        ├── 3a. DistilBERT lr=2e-5  (GPU) ─┐
        ├── 3b. DistilBERT lr=5e-5  (GPU) ─┼── paralelo
        └── 3c. DistilBERT lr=1e-4  (GPU) ─┘
                    │
        4. Avaliar e selecionar (MLflow)
                    │
        5. Publicar modelo aprovado (S3 + Registry)
```

## Arquivos

| Arquivo | Função |
|---------|--------|
| `banking77_training_pipeline.py` | Definição KFP 2.x |
| `compile_pipeline.py` | Gera YAML importável |
| `banking77-customer-intent-pipeline.yaml` | Pipeline compilado (importar no dashboard) |
| `requirements.txt` | kfp 2.16 (compilação local) |

## Importar no OpenShift AI

```bash
./scripts/upload-pipeline.sh
```

No dashboard:

1. **Projects** → `customer-intent-demo`
2. **Pipelines** → **Import pipeline**
3. Selecione `pipelines/banking77-customer-intent-pipeline.yaml`
4. **Create run** com:
   - Service account: `customer-intent-pipeline`
   - GPU disponível (pausar Qwen se necessário)

## Pré-requisitos

- Componente `aipipelines` Managed no DataScienceCluster
- Código em `/opt/app-root/src/customer-intent-demo` no PVC `banking77-training`
- Secret `customer-intent-s3-connection` no namespace
- RBAC: `openshift/14-pipeline-rbac.yaml`

## Recompilar após alterações

```bash
cd pipelines
pip install -r requirements.txt
python compile_pipeline.py
```

## Apresentação sugerida (5 min)

1. Mostre o treino manual concluído (MLflow com 4+ runs)
2. Importe o pipeline e mostre o **grafo** — mesmos passos, visual diferente
3. Execute um run (ou mostre run anterior) — etapas verdes, logs por componente
4. Compare: manual = exploração; pipeline = operação repetível com approval gate
