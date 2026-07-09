#!/usr/bin/env python3
"""Compara runs MLflow, analisa thresholds e seleciona modelo aprovado."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import mlflow
import pandas as pd

from common import ROOT, load_configs, setup_mlflow


def fetch_runs(experiment_name: str) -> pd.DataFrame:
    experiment = mlflow.get_experiment_by_name(experiment_name)
    if experiment is None:
        raise RuntimeError(f"Experiment not found: {experiment_name}")
    runs = mlflow.search_runs(
        experiment_ids=[experiment.experiment_id],
        order_by=["metrics.validation_macro_f1 DESC"],
    )
    return runs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default=str(ROOT / "reports"))
    parser.add_argument("--min-validation-macro-f1", type=float, help="Minimum macro F1 for approval")
    parser.add_argument(
        "--max-incorrect-auto-routing-rate",
        type=float,
        help="Maximum incorrect auto-routing rate for approval",
    )
    parser.add_argument("--routing-threshold", type=float, help="Confidence threshold for auto-routing")
    args = parser.parse_args()

    config, _ = load_configs()
    setup_mlflow(config)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    criteria = dict(config["approval_criteria"])
    if args.min_validation_macro_f1 is not None:
        criteria["min_validation_macro_f1"] = args.min_validation_macro_f1
    if args.max_incorrect_auto_routing_rate is not None:
        criteria["max_incorrect_auto_routing_rate"] = args.max_incorrect_auto_routing_rate
    default_threshold = (
        args.routing_threshold
        if args.routing_threshold is not None
        else config["default_threshold"]
    )

    runs = fetch_runs(config["mlflow"]["experiment_name"])
    if runs.empty:
        raise RuntimeError("No MLflow runs found. Execute training first.")

    cols = [
        "run_id",
        "tags.mlflow.runName",
        "metrics.validation_macro_f1",
        "metrics.validation_incorrect_auto_routing_rate",
        "metrics.validation_automation_coverage",
        "metrics.inference_latency_p95",
        "metrics.test_macro_f1",
    ]
    available = [c for c in cols if c in runs.columns]
    summary = runs[available].copy()
    summary_path = output_dir / "run-comparison.csv"
    summary.to_csv(summary_path, index=False)

    filtered = summary
    if "metrics.validation_macro_f1" in summary.columns:
        filtered = filtered[
            filtered["metrics.validation_macro_f1"] >= criteria["min_validation_macro_f1"]
        ]
    if "metrics.validation_incorrect_auto_routing_rate" in summary.columns:
        filtered = filtered[
            filtered["metrics.validation_incorrect_auto_routing_rate"]
            <= criteria["max_incorrect_auto_routing_rate"]
        ]

    winner = filtered.iloc[0] if not filtered.empty else summary.iloc[0]
    fallback_used = filtered.empty

    ranked = []
    for _, row in summary.iterrows():
        entry = {
            "run_id": row.get("run_id"),
            "run_name": row.get("tags.mlflow.runName"),
            "validation_macro_f1": row.get("metrics.validation_macro_f1"),
            "validation_incorrect_auto_routing_rate": row.get(
                "metrics.validation_incorrect_auto_routing_rate"
            ),
            "inference_latency_p95": row.get("metrics.inference_latency_p95"),
            "passes_macro_f1": (
                row.get("metrics.validation_macro_f1", 0) >= criteria["min_validation_macro_f1"]
                if "metrics.validation_macro_f1" in row
                else None
            ),
            "passes_routing_rate": (
                row.get("metrics.validation_incorrect_auto_routing_rate", 1)
                <= criteria["max_incorrect_auto_routing_rate"]
                if "metrics.validation_incorrect_auto_routing_rate" in row
                else None
            ),
        }
        ranked.append(entry)

    decision = {
        "selected_run_id": winner["run_id"],
        "selected_run_name": winner.get("tags.mlflow.runName"),
        "selection_method": (
            "highest validation_macro_f1 among runs passing approval_criteria"
            if not fallback_used
            else "fallback: highest validation_macro_f1 (no run passed all criteria)"
        ),
        "approval_criteria": criteria,
        "thresholds_evaluated": config["thresholds"],
        "default_threshold": default_threshold,
        "ranked_runs": ranked,
        "runs_passing_criteria": int(len(filtered)),
    }
    decision_path = output_dir / "model-selection.json"
    decision_path.write_text(json.dumps(decision, indent=2, default=str), encoding="utf-8")

    with mlflow.start_run(run_name="model-selection"):
        mlflow.log_artifact(str(summary_path))
        mlflow.log_artifact(str(decision_path))
        mlflow.log_param("selected_run_id", winner["run_id"])

    print(json.dumps(decision, indent=2, default=str))


if __name__ == "__main__":
    main()
