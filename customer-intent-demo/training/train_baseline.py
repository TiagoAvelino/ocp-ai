#!/usr/bin/env python3
"""Experimento 1: TF-IDF + Logistic Regression."""

from __future__ import annotations

import argparse
import json
import pickle
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline

import mlflow
from common import (
    ROOT,
    business_metrics,
    classification_metrics,
    load_configs,
    log_classification_artifacts,
    measure_latency,
    setup_mlflow,
)


def load_split(data_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, dict]:
    train = pd.read_json(data_dir / "train.jsonl", lines=True)
    val = pd.read_json(data_dir / "validation.jsonl", lines=True)
    test = pd.read_json(data_dir / "test.jsonl", lines=True)
    label_map = json.loads((data_dir / "label-map.json").read_text(encoding="utf-8"))
    return train, val, test, label_map


def predict_with_confidence(pipeline: Pipeline, texts: list[str]) -> tuple[list[int], list[float]]:
    probs = pipeline.predict_proba(texts)
    preds = probs.argmax(axis=1).tolist()
    confidences = probs.max(axis=1).tolist()
    return preds, confidences


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default=str(ROOT / "data" / "prepared"))
    parser.add_argument("--output-dir", default=str(ROOT / "artifacts" / "baseline"))
    args = parser.parse_args()

    config, _ = load_configs()
    setup_mlflow(config)
    exp_cfg = config["experiments"]["baseline"]
    data_dir = Path(args.data_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    train, val, test, label_map = load_split(data_dir)
    labels = [label_map["id2label"][str(i)] for i in range(len(label_map["id2label"]))]

    pipeline = Pipeline(
        [
            (
                "tfidf",
                TfidfVectorizer(
                    max_features=exp_cfg["max_features"],
                    ngram_range=tuple(exp_cfg["ngram_range"]),
                ),
            ),
            ("clf", LogisticRegression(max_iter=1000, C=exp_cfg["C"])),
        ]
    )

    with mlflow.start_run(run_name=exp_cfg["run_name"]):
        mlflow.log_params(
            {
                "model_name": "tfidf-logistic-regression",
                "dataset_name": config["dataset"]["name"],
                "selected_intents": ",".join(label_map["selected_intents"]),
                "max_features": exp_cfg["max_features"],
                "C": exp_cfg["C"],
                "decision_threshold": config["default_threshold"],
            }
        )

        pipeline.fit(train["text"], train["label_id"])
        val_pred, val_conf = predict_with_confidence(pipeline, val["text"].tolist())
        test_pred, test_conf = predict_with_confidence(pipeline, test["text"].tolist())

        val_metrics = classification_metrics(val["label_id"].tolist(), val_pred)
        test_metrics = classification_metrics(test["label_id"].tolist(), test_pred)
        for key, value in val_metrics.items():
            mlflow.log_metric(f"validation_{key}", value)
        for key, value in test_metrics.items():
            mlflow.log_metric(f"test_{key}", value)

        biz = business_metrics(
            val["label_id"].tolist(),
            val_pred,
            val_conf,
            config["default_threshold"],
        )
        mlflow.log_metrics({f"validation_{k}": v for k, v in biz.items()})

        latency = measure_latency(
            lambda text: predict_with_confidence(pipeline, [text])[0],
            val["text"].tolist()[:20],
        )
        mlflow.log_metrics(latency)

        log_classification_artifacts(
            val["label_id"].tolist(),
            val_pred,
            labels,
            output_dir,
            "validation",
        )

        model_path = output_dir / "baseline-model.pkl"
        with model_path.open("wb") as handle:
            pickle.dump({"pipeline": pipeline, "label_map": label_map}, handle)
        mlflow.log_artifact(str(model_path))
        mlflow.sklearn.log_model(pipeline, artifact_path="model")

        print(json.dumps({"validation": val_metrics, "test": test_metrics, "business": biz}, indent=2))


if __name__ == "__main__":
    main()
