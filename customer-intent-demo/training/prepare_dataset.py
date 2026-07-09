#!/usr/bin/env python3
"""Prepara Banking77 (12 intenções) e salva artefatos local/S3."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import pandas as pd
from sklearn.model_selection import train_test_split

from common import INTENT_PATH, ROOT, load_banking77, load_configs, load_yaml, setup_mlflow
import mlflow


def filter_and_split(seed: int, val_ratio: float) -> dict:
    intent_cfg = load_yaml(INTENT_PATH)
    selected = intent_cfg["selected_intents"]
    label2id = {label: idx for idx, label in enumerate(selected)}

    dataset = load_banking77()
    label_names = dataset["train"].features["label"].names
    train_df = pd.DataFrame(dataset["train"])
    test_df = pd.DataFrame(dataset["test"])
    train_df["label_text"] = train_df["label"].map(lambda idx: label_names[idx])
    test_df["label_text"] = test_df["label"].map(lambda idx: label_names[idx])

    train_df = train_df[train_df["label_text"].isin(selected)].copy()
    test_df = test_df[test_df["label_text"].isin(selected)].copy()
    train_df["label_id"] = train_df["label_text"].map(label2id)
    test_df["label_id"] = test_df["label_text"].map(label2id)

    train_part, val_part = train_test_split(
        train_df,
        test_size=val_ratio,
        random_state=seed,
        stratify=train_df["label_id"],
    )

    return {
        "train": train_part.reset_index(drop=True),
        "validation": val_part.reset_index(drop=True),
        "test": test_df.reset_index(drop=True),
        "label2id": label2id,
        "id2label": {idx: label for label, idx in label2id.items()},
        "selected_intents": selected,
    }


def upload_s3(local_dir: Path, bucket: str, prefix: str) -> None:
    import boto3

    client = boto3.client("s3", endpoint_url=os.environ.get("AWS_S3_ENDPOINT"))
    for path in local_dir.rglob("*"):
        if path.is_file():
            key = f"{prefix}/{path.relative_to(local_dir)}"
            client.upload_file(str(path), bucket, key)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default=str(ROOT / "data" / "prepared"))
    parser.add_argument("--upload-s3", action="store_true")
    parser.add_argument("--seed", type=int, help="Override dataset split seed")
    parser.add_argument("--validation-split", type=float, help="Override validation split ratio")
    args = parser.parse_args()

    config, intent_cfg = load_configs()
    setup_mlflow(config)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    seed = args.seed if args.seed is not None else config["dataset"]["seed"]
    val_ratio = (
        args.validation_split
        if args.validation_split is not None
        else config["dataset"]["validation_split"]
    )
    split = filter_and_split(seed, val_ratio)

    split["train"].to_json(output_dir / "train.jsonl", orient="records", lines=True)
    split["validation"].to_json(output_dir / "validation.jsonl", orient="records", lines=True)
    split["test"].to_json(output_dir / "test.jsonl", orient="records", lines=True)

    label_map = {
        "label2id": split["label2id"],
        "id2label": split["id2label"],
        "selected_intents": split["selected_intents"],
        "intent_to_department": intent_cfg["intent_to_department"],
        "departments": intent_cfg["departments"],
        "license": intent_cfg["license"],
        "dataset": intent_cfg["dataset"],
    }
    (output_dir / "label-map.json").write_text(json.dumps(label_map, indent=2), encoding="utf-8")

    summary = {
        "dataset_name": config["dataset"]["name"],
        "dataset_revision": config["dataset"]["revision"],
        "selected_intents": split["selected_intents"],
        "train_size": len(split["train"]),
        "validation_size": len(split["validation"]),
        "test_size": len(split["test"]),
        "seed": seed,
        "validation_split": val_ratio,
        "license": intent_cfg["license"],
        "preparation_script_version": "1.0.0",
    }
    (output_dir / "dataset-summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    with mlflow.start_run(run_name="dataset-preparation"):
        mlflow.log_params(summary)
        mlflow.log_artifact(str(output_dir / "label-map.json"))
        mlflow.log_artifact(str(output_dir / "dataset-summary.json"))

    if args.upload_s3:
        bucket = config["s3"]["bucket"]
        prefix = config["s3"]["paths"]["prepared"]
        upload_s3(output_dir, bucket, prefix)
        print(f"Uploaded to s3://{bucket}/{prefix}")

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
