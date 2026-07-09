"""
Pipeline Kubeflow - Customer Intent (Banking77)
"""

from kfp import dsl
from kfp.dsl import component

BASE_IMAGE = (
    "image-registry.openshift-image-registry.svc:5000/"
    "redhat-ods-applications/pytorch:3.4"
)
WORKSPACE_PVC = "banking77-training"
PIPELINE_PACKAGES = [
    "datasets>=3.0.0",
    "transformers>=4.40.0",
    "scikit-learn>=1.4.0",
    "pandas>=2.2.0",
    "matplotlib>=3.8.0",
    "seaborn>=0.13.0",
    "pyyaml>=6.0.0",
    "boto3>=1.34.0",
    'mlflow[kubernetes]>=3.11.0',
    "safetensors>=0.4.0",
    "accelerate>=0.30.0",
]


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def prepare_dataset(random_seed: int, validation_split: float):
    """Filtra 12 intencoes Banking77, divide dados e envia ao S3."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [
        sys.executable,
        f"{project_root}/training/prepare_dataset.py",
        "--upload-s3",
        "--seed",
        str(random_seed),
        "--validation-split",
        str(validation_split),
    ]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def train_baseline():
    """Baseline TF-IDF + Logistic Regression (referencia CPU)."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [sys.executable, f"{project_root}/training/train_baseline.py"]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def train_distilbert_conservative(learning_rate: float, epochs: int):
    """DistilBERT conservador (GPU)."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [
        sys.executable,
        f"{project_root}/training/train_distilbert.py",
        "--experiment",
        "distilbert_conservative",
        "--learning-rate",
        str(learning_rate),
        "--epochs",
        str(epochs),
    ]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def train_distilbert_intermediate(learning_rate: float, epochs: int):
    """DistilBERT intermediario (GPU)."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [
        sys.executable,
        f"{project_root}/training/train_distilbert.py",
        "--experiment",
        "distilbert_intermediate",
        "--learning-rate",
        str(learning_rate),
        "--epochs",
        str(epochs),
    ]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def train_distilbert_aggressive(learning_rate: float, epochs: int):
    """DistilBERT agressivo (GPU)."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [
        sys.executable,
        f"{project_root}/training/train_distilbert.py",
        "--experiment",
        "distilbert_aggressive",
        "--learning-rate",
        str(learning_rate),
        "--epochs",
        str(epochs),
    ]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def evaluate_and_select(
    min_validation_macro_f1: float,
    max_incorrect_auto_routing_rate: float,
    routing_threshold: float,
):
    """Compara runs MLflow, analisa thresholds e seleciona o vencedor."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [
        sys.executable,
        f"{project_root}/training/evaluate_and_select.py",
        "--min-validation-macro-f1",
        str(min_validation_macro_f1),
        "--max-incorrect-auto-routing-rate",
        str(max_incorrect_auto_routing_rate),
        "--routing-threshold",
        str(routing_threshold),
    ]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


@component(base_image=BASE_IMAGE, packages_to_install=PIPELINE_PACKAGES)
def publish_approved_model():
    """Exporta modelo aprovado -> S3 -> Model Registry."""
    import os
    import subprocess
    import sys

    project_root = "/opt/app-root/src/customer-intent-demo"
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("HF_HOME", "/opt/app-root/src/model-cache")
    os.environ.setdefault("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    cmd = [sys.executable, f"{project_root}/training/publish_approved_model.py"]
    print(">>>", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=project_root)


def _configure_common(task: dsl.PipelineTask) -> dsl.PipelineTask:
    import kfp.kubernetes as k8s

    k8s.mount_pvc(task, pvc_name=WORKSPACE_PVC, mount_path="/opt/app-root/src")
    task.set_env_variable("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    task.set_env_variable("HF_HOME", "/opt/app-root/src/model-cache")
    task.set_env_variable("TRANSFORMERS_CACHE", "/opt/app-root/src/model-cache")
    k8s.use_secret_as_env(
        task,
        secret_name="customer-intent-s3-connection",
        secret_key_to_env={
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
            "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_S3_BUCKET": "AWS_S3_BUCKET",
        },
    )
    return task


def _configure_gpu(task: dsl.PipelineTask) -> dsl.PipelineTask:
    import kfp.kubernetes as k8s

    task.set_accelerator_type("nvidia.com/gpu")
    task.set_accelerator_limit(1)
    k8s.add_toleration(
        task,
        key="nvidia.com/gpu",
        operator="Exists",
        effect="NoSchedule",
    )
    task.set_cpu_limit("4")
    task.set_memory_limit("16Gi")
    task.set_cpu_request("4")
    task.set_memory_request("16Gi")
    return task


@dsl.pipeline(
    name="banking77-customer-intent-training",
    description=(
        "Pipeline reproduzivel: preparacao Banking77 (12 intencoes), baseline, "
        "3 fine-tunings DistilBERT em sequencia (1 GPU), selecao MLflow e "
        "publicacao do modelo aprovado."
    ),
)
def banking77_customer_intent_training(
    random_seed: int = 42,
    validation_split: float = 0.1,
    lr_conservative: float = 2e-5,
    epochs_conservative: int = 2,
    lr_intermediate: float = 5e-5,
    epochs_intermediate: int = 3,
    lr_aggressive: float = 1e-4,
    epochs_aggressive: int = 3,
    min_validation_macro_f1: float = 0.75,
    max_incorrect_auto_routing_rate: float = 0.08,
    routing_threshold: float = 0.80,
):
    prep = _configure_common(
        prepare_dataset(
            random_seed=random_seed,
            validation_split=validation_split,
        )
    )
    prep.set_display_name("1. Preparar dataset")
    prep.set_caching_options(enable_caching=False)

    baseline = _configure_common(train_baseline())
    baseline.set_display_name("2. Baseline TF-IDF")
    baseline.after(prep)
    baseline.set_caching_options(enable_caching=False)

    d1 = _configure_gpu(
        _configure_common(
            train_distilbert_conservative(
                learning_rate=lr_conservative,
                epochs=epochs_conservative,
            )
        )
    )
    d1.set_display_name("3a. DistilBERT conservador")
    d1.after(baseline)

    d2 = _configure_gpu(
        _configure_common(
            train_distilbert_intermediate(
                learning_rate=lr_intermediate,
                epochs=epochs_intermediate,
            )
        )
    )
    d2.set_display_name("3b. DistilBERT intermediario")
    d2.after(d1)

    d3 = _configure_gpu(
        _configure_common(
            train_distilbert_aggressive(
                learning_rate=lr_aggressive,
                epochs=epochs_aggressive,
            )
        )
    )
    d3.set_display_name("3c. DistilBERT agressivo")
    d3.after(d2)

    for task in (d1, d2, d3):
        task.set_caching_options(enable_caching=False)

    evaluate = _configure_common(
        evaluate_and_select(
            min_validation_macro_f1=min_validation_macro_f1,
            max_incorrect_auto_routing_rate=max_incorrect_auto_routing_rate,
            routing_threshold=routing_threshold,
        )
    )
    evaluate.set_display_name("4. Avaliar e selecionar")
    evaluate.after(baseline, d1, d2, d3)
    evaluate.set_caching_options(enable_caching=False)

    publish = _configure_common(publish_approved_model())
    publish.set_display_name("5. Publicar modelo aprovado")
    publish.after(evaluate)
    publish.set_caching_options(enable_caching=False)
