#!/usr/bin/env python3
"""
Experimento MLflow — Banking77 (customer-intent-demo)

Registra 4 runs comparáveis no experimento ``banking77-customer-intent``:

  1. baseline-tfidf-logistic-regression
  2. distilbert-lr-2e-5-epochs-2   (conservador)
  3. distilbert-lr-5e-5-epochs-3   (intermediário)
  4. distilbert-lr-1e-4-epochs-3   (agressivo)

Após os treinos, gera ``reports/model-selection.json`` via evaluate_and_select.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import mlflow
from mlflow.tracking import MlflowClient

from common import ROOT, load_configs, setup_mlflow

TRAINING = ROOT / "training"

DISTILBERT_EXPERIMENTS = (
    "distilbert_conservative",
    "distilbert_intermediate",
    "distilbert_aggressive",
)


def run_script(script: str, *extra: str) -> None:
    cmd = [sys.executable, str(TRAINING / script), *extra]
    print(f"\n>>> {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, check=True, cwd=ROOT)


def print_mlflow_summary(config: dict) -> None:
    setup_mlflow(config)
    client = MlflowClient()
    experiment = mlflow.get_experiment_by_name(config["mlflow"]["experiment_name"])
    if experiment is None:
        print("Experimento MLflow ainda não existe.")
        return

    expected_names = {
        config["experiments"]["baseline"]["run_name"],
        *[config["experiments"][key]["run_name"] for key in DISTILBERT_EXPERIMENTS],
    }
    runs = client.search_runs(
        experiment_ids=[experiment.experiment_id],
        filter_string="attributes.status = 'FINISHED'",
        order_by=["attributes.start_time DESC"],
        max_results=50,
    )
    summary = []
    seen: set[str] = set()
    for run in runs:
        name = run.info.run_name or ""
        if name not in expected_names or name in seen:
            continue
        seen.add(name)
        summary.append(
            {
                "run_name": name,
                "run_id": run.info.run_id,
                "validation_macro_f1": run.data.metrics.get("validation_macro_f1"),
            }
        )

    print("\n=== Runs MLflow deste experimento ===")
    print(json.dumps(summary, indent=2, default=str))
    selection = ROOT / "reports" / "model-selection.json"
    if selection.exists():
        print("\n=== Seleção ===")
        print(selection.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Experimento MLflow Banking77")
    parser.add_argument(
        "--skip-prepare",
        action="store_true",
        help="Pula prepare_dataset (use se data/prepared já existir)",
    )
    parser.add_argument(
        "--skip-evaluate",
        action="store_true",
        help="Não executa evaluate_and_select ao final",
    )
    args = parser.parse_args()

    config, _ = load_configs()
    setup_mlflow(config)
    mlflow.set_experiment(config["mlflow"]["experiment_name"])

    print(
        "Experimento MLflow:",
        config["mlflow"]["experiment_name"],
        "| runs:",
        len(DISTILBERT_EXPERIMENTS) + 1,
        "modelos",
        flush=True,
    )

    if not args.skip_prepare:
        run_script("prepare_dataset.py", "--upload-s3")

    run_script("train_baseline.py")

    for experiment_key in DISTILBERT_EXPERIMENTS:
        run_script("train_distilbert.py", "--experiment", experiment_key)

    if not args.skip_evaluate:
        run_script("evaluate_and_select.py")

    print_mlflow_summary(config)
    print("\nExperimento concluído.", flush=True)


if __name__ == "__main__":
    main()
