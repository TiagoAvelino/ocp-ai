#!/usr/bin/env python3
"""Fine-tuning DistilBERT para classificação de intenção."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    Trainer,
    TrainingArguments,
)

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


class IntentDataset(Dataset):
    def __init__(self, texts, labels, tokenizer, max_length):
        self.texts = texts
        self.labels = labels
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self):
        return len(self.texts)

    def __getitem__(self, idx):
        encoded = self.tokenizer(
            self.texts[idx],
            truncation=True,
            padding="max_length",
            max_length=self.max_length,
            return_tensors="pt",
        )
        item = {k: v.squeeze(0) for k, v in encoded.items()}
        item["labels"] = torch.tensor(self.labels[idx], dtype=torch.long)
        return item


def load_split(data_dir: Path):
    train = pd.read_json(data_dir / "train.jsonl", lines=True)
    val = pd.read_json(data_dir / "validation.jsonl", lines=True)
    test = pd.read_json(data_dir / "test.jsonl", lines=True)
    label_map = json.loads((data_dir / "label-map.json").read_text(encoding="utf-8"))
    return train, val, test, label_map


def predict(model, tokenizer, texts, max_length, device):
    model.eval()
    preds, confidences = [], []
    with torch.no_grad():
        for text in texts:
            encoded = tokenizer(
                text,
                truncation=True,
                padding=True,
                max_length=max_length,
                return_tensors="pt",
            ).to(device)
            outputs = model(**encoded)
            probs = torch.softmax(outputs.logits, dim=-1).cpu().numpy()[0]
            preds.append(int(probs.argmax()))
            confidences.append(float(probs.max()))
    return preds, confidences


def train_experiment(
    experiment_key: str,
    data_dir: Path,
    output_dir: Path,
    learning_rate: float | None = None,
    epochs: int | None = None,
) -> None:
    config, _ = load_configs()
    setup_mlflow(config)
    exp_cfg = dict(config["experiments"][experiment_key])
    if learning_rate is not None:
        exp_cfg["learning_rate"] = learning_rate
    if epochs is not None:
        exp_cfg["epochs"] = epochs
    train, val, test, label_map = load_split(data_dir)
    labels = [label_map["id2label"][str(i)] for i in range(len(label_map["id2label"]))]

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    tokenizer = AutoTokenizer.from_pretrained(exp_cfg["model_name"])
    model = AutoModelForSequenceClassification.from_pretrained(
        exp_cfg["model_name"],
        num_labels=len(labels),
        id2label={int(k): v for k, v in label_map["id2label"].items()},
        label2id=label_map["label2id"],
    ).to(device)

    train_ds = IntentDataset(
        train["text"].tolist(),
        train["label_id"].tolist(),
        tokenizer,
        exp_cfg["max_length"],
    )
    val_ds = IntentDataset(
        val["text"].tolist(),
        val["label_id"].tolist(),
        tokenizer,
        exp_cfg["max_length"],
    )

    run_output = output_dir / exp_cfg["run_name"]
    run_output.mkdir(parents=True, exist_ok=True)

    with mlflow.start_run(run_name=exp_cfg["run_name"]):
        mlflow.log_params(
            {
                "model_name": exp_cfg["model_name"],
                "dataset_name": config["dataset"]["name"],
                "learning_rate": exp_cfg["learning_rate"],
                "epochs": exp_cfg["epochs"],
                "batch_size": exp_cfg["batch_size"],
                "max_length": exp_cfg["max_length"],
                "weight_decay": exp_cfg["weight_decay"],
                "decision_threshold": config["default_threshold"],
            }
        )

        start = time.time()
        training_args = TrainingArguments(
            output_dir=str(run_output / "checkpoints"),
            num_train_epochs=exp_cfg["epochs"],
            per_device_train_batch_size=exp_cfg["batch_size"],
            per_device_eval_batch_size=exp_cfg["batch_size"],
            learning_rate=exp_cfg["learning_rate"],
            weight_decay=exp_cfg["weight_decay"],
            eval_strategy="epoch",
            save_strategy="no",
            logging_steps=20,
            report_to=[],
        )
        trainer = Trainer(model=model, args=training_args, train_dataset=train_ds, eval_dataset=val_ds)
        trainer.train()
        mlflow.log_metric("training_runtime", time.time() - start)

        val_pred, val_conf = predict(
            model, tokenizer, val["text"].tolist(), exp_cfg["max_length"], device
        )
        test_pred, test_conf = predict(
            model, tokenizer, test["text"].tolist(), exp_cfg["max_length"], device
        )

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
            lambda text: predict(model, tokenizer, [text], exp_cfg["max_length"], device)[0],
            val["text"].tolist()[:20],
        )
        mlflow.log_metrics(latency)

        log_classification_artifacts(
            val["label_id"].tolist(),
            val_pred,
            labels,
            run_output,
            "validation",
        )

        model.save_pretrained(run_output)
        tokenizer.save_pretrained(run_output)
        (run_output / "label-map.json").write_text(
            json.dumps(label_map, indent=2), encoding="utf-8"
        )
        mlflow.log_artifacts(str(run_output), artifact_path="model")
        mlflow.pytorch.log_model(model, artifact_path="pytorch-model")

        print(json.dumps({"experiment": experiment_key, "validation": val_metrics, "test": test_metrics}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--experiment",
        choices=[
            "distilbert_conservative",
            "distilbert_intermediate",
            "distilbert_aggressive",
        ],
        required=True,
    )
    parser.add_argument("--data-dir", default=str(ROOT / "data" / "prepared"))
    parser.add_argument("--output-dir", default=str(ROOT / "artifacts" / "distilbert"))
    parser.add_argument("--learning-rate", type=float, help="Override experiment learning rate")
    parser.add_argument("--epochs", type=int, help="Override experiment epoch count")
    args = parser.parse_args()
    train_experiment(
        args.experiment,
        Path(args.data_dir),
        Path(args.output_dir),
        learning_rate=args.learning_rate,
        epochs=args.epochs,
    )


if __name__ == "__main__":
    main()
