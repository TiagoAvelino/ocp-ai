#!/usr/bin/env python3
"""Publica o modelo vencedor: exporta artefatos, envia ao S3 e registra no MLflow."""

from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path

import boto3

from common import ROOT, load_configs, setup_mlflow
from register_model import main as register_main


def upload_directory(local_dir: Path, bucket: str, prefix: str) -> None:
    client = boto3.client("s3", endpoint_url=os.environ.get("AWS_S3_ENDPOINT"))
    for path in local_dir.rglob("*"):
        if path.is_file():
            key = f"{prefix}/{path.relative_to(local_dir)}"
            client.upload_file(str(path), bucket, key)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--selection-file",
        default=str(ROOT / "reports" / "model-selection.json"),
    )
    args = parser.parse_args()

    config, _ = load_configs()
    selection = json.loads(Path(args.selection_file).read_text(encoding="utf-8"))
    run_id = selection["selected_run_id"]
    run_name = selection["selected_run_name"]

    src = ROOT / "artifacts" / "distilbert" / run_name
    if not src.exists():
        raise FileNotFoundError(f"Model directory not found: {src}")

    approved = ROOT / "artifacts" / "approved-model"
    if approved.exists():
        shutil.rmtree(approved)
    shutil.copytree(src, approved)

    bucket = config["s3"]["bucket"]
    prefix = f"{config['s3']['paths']['models']}/approved"
    upload_directory(approved, bucket, prefix)

    setup_mlflow(config)
    import sys

    sys.argv = [
        "register_model.py",
        "--run-id",
        run_id,
        "--stage",
        "Approved",
    ]
    register_main()

    print(
        json.dumps(
            {
                "selected_run_id": run_id,
                "selected_run_name": run_name,
                "s3_path": f"s3://{bucket}/{prefix}",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
