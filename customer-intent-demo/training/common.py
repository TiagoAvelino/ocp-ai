"""Utilitários compartilhados para treino Banking77 + MLflow."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

import mlflow
import numpy as np
import yaml
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "training_config.yaml"
INTENT_PATH = ROOT / "config" / "intent_mapping.yaml"


def load_banking77():
    """Carrega Banking77 via CSV público (compatível com datasets 3.x / Python 3.12)."""
    import json
    import urllib.request

    import pandas as pd
    from datasets import ClassLabel, Dataset, DatasetDict, Features, Value

    infos_url = (
        "https://huggingface.co/datasets/PolyAI/banking77/raw/main/dataset_infos.json"
    )
    train_url = (
        "https://raw.githubusercontent.com/PolyAI-LDN/task-specific-datasets/"
        "master/banking_data/train.csv"
    )
    test_url = (
        "https://raw.githubusercontent.com/PolyAI-LDN/task-specific-datasets/"
        "master/banking_data/test.csv"
    )

    label_names = json.loads(
        urllib.request.urlopen(infos_url, timeout=120).read().decode()
    )["default"]["features"]["label"]["names"]
    label2id = {name: idx for idx, name in enumerate(label_names)}
    features = Features(
        {
            "text": Value("string"),
            "label": ClassLabel(names=label_names),
        }
    )

    def _load_split(url: str) -> Dataset:
        frame = pd.read_csv(url)
        frame["label"] = frame["category"].map(label2id)
        frame = frame[["text", "label"]].dropna()
        return Dataset.from_pandas(frame, features=features, preserve_index=False)

    return DatasetDict(train=_load_split(train_url), test=_load_split(test_url))


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_configs() -> tuple[dict[str, Any], dict[str, Any]]:
    return load_yaml(CONFIG_PATH), load_yaml(INTENT_PATH)


def setup_mlflow(config: dict[str, Any]) -> str:
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    tracking_uri = config["mlflow"].get("tracking_uri")
    if tracking_uri:
        os.environ.setdefault("MLFLOW_TRACKING_URI", tracking_uri)
        os.environ.setdefault("SSL_CERT_FILE", "/etc/pki/tls/custom-certs/ca-bundle.crt")
        os.environ.setdefault("REQUESTS_CA_BUNDLE", "/etc/pki/tls/custom-certs/ca-bundle.crt")
        os.environ.setdefault(
            "MLFLOW_S3_ENDPOINT_URL", "http://minio.minio.svc.cluster.local:9000"
        )
    mlflow.set_experiment(config["mlflow"]["experiment_name"])
    return config["mlflow"]["experiment_name"]


def business_metrics(
    y_true: list[int],
    y_pred: list[int],
    confidences: list[float],
    threshold: float,
) -> dict[str, float]:
    auto_mask = [c >= threshold for c in confidences]
    auto_total = sum(auto_mask)
    coverage = auto_total / len(confidences) if confidences else 0.0
    human_review_rate = 1.0 - coverage

    auto_correct = 0
    auto_incorrect = 0
    for truth, pred, conf, auto in zip(y_true, y_pred, confidences, auto_mask):
        if not auto:
            continue
        if truth == pred:
            auto_correct += 1
        else:
            auto_incorrect += 1

    incorrect_auto_routing_rate = (
        auto_incorrect / auto_total if auto_total else 0.0
    )
    low_confidence_rate = human_review_rate
    return {
        "automation_coverage": coverage,
        "human_review_rate": human_review_rate,
        "incorrect_auto_routing_rate": incorrect_auto_routing_rate,
        "low_confidence_rate": low_confidence_rate,
        "routing_accuracy_auto_only": (
            auto_correct / auto_total if auto_total else 0.0
        ),
    }


def classification_metrics(y_true: list[int], y_pred: list[int]) -> dict[str, float]:
    return {
        "accuracy": float(np.mean(np.array(y_true) == np.array(y_pred))),
        "macro_f1": float(f1_score(y_true, y_pred, average="macro", zero_division=0)),
        "macro_precision": float(
            precision_score(y_true, y_pred, average="macro", zero_division=0)
        ),
        "macro_recall": float(
            recall_score(y_true, y_pred, average="macro", zero_division=0)
        ),
    }


def log_classification_artifacts(
    y_true: list[int],
    y_pred: list[int],
    labels: list[str],
    output_dir: Path,
    prefix: str,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    report = classification_report(
        y_true, y_pred, target_names=labels, output_dict=True, zero_division=0
    )
    report_path = output_dir / f"{prefix}-classification-report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    mlflow.log_artifact(str(report_path))

    matrix = confusion_matrix(y_true, y_pred)
    matrix_path = output_dir / f"{prefix}-confusion-matrix.json"
    matrix_path.write_text(
        json.dumps({"labels": labels, "matrix": matrix.tolist()}, indent=2),
        encoding="utf-8",
    )
    mlflow.log_artifact(str(matrix_path))

    try:
        import matplotlib.pyplot as plt
        import seaborn as sns

        fig, ax = plt.subplots(figsize=(10, 8))
        sns.heatmap(matrix, annot=True, fmt="d", xticklabels=labels, yticklabels=labels, ax=ax)
        ax.set_title(f"Confusion matrix ({prefix})")
        fig.tight_layout()
        png_path = output_dir / f"{prefix}-confusion-matrix.png"
        fig.savefig(png_path, dpi=120)
        plt.close(fig)
        mlflow.log_artifact(str(png_path))
    except ImportError:
        pass


def measure_latency(predict_fn, samples: list[str], warmup: int = 3) -> dict[str, float]:
    for sample in samples[:warmup]:
        predict_fn(sample)

    latencies_ms: list[float] = []
    for sample in samples:
        start = time.perf_counter()
        predict_fn(sample)
        latencies_ms.append((time.perf_counter() - start) * 1000)

    arr = np.array(latencies_ms)
    return {
        "inference_latency_p50": float(np.percentile(arr, 50)),
        "inference_latency_p95": float(np.percentile(arr, 95)),
    }
