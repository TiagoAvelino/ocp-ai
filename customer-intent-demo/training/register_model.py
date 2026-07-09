#!/usr/bin/env python3
"""Registra modelo aprovado no MLflow Model Registry."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import mlflow
from mlflow.tracking import MlflowClient

from common import ROOT, load_configs, setup_mlflow


def _search_logged_model_uris(client: MlflowClient, run_id: str, experiment_id: str) -> list[str]:
    uris: list[str] = []
    filters = (f"run_id='{run_id}'", f"source_run_id='{run_id}'")
    for filter_string in filters:
        try:
            logged = client.search_logged_models(
                experiment_ids=[experiment_id],
                filter_string=filter_string,
            )
        except TypeError:
            logged = client.search_logged_models(filter_string=filter_string)
        except Exception:
            continue
        for model in logged:
            uri = getattr(model, "model_uri", None)
            if uri and uri not in uris:
                uris.append(uri)
    return uris


def resolve_model_uri(client: MlflowClient, run_id: str, experiment_id: str) -> str:
    preferred_names = ("pytorch-model", "model")
    for filter_string in (f"run_id='{run_id}'", f"source_run_id='{run_id}'"):
        try:
            logged = client.search_logged_models(
                experiment_ids=[experiment_id],
                filter_string=filter_string,
            )
        except TypeError:
            logged = client.search_logged_models(filter_string=filter_string)
        except Exception:
            continue
        for name in preferred_names:
            match = next((m for m in logged if getattr(m, "name", None) == name), None)
            if match and getattr(match, "model_uri", None):
                return match.model_uri
        if logged and getattr(logged[0], "model_uri", None):
            return logged[0].model_uri

    for uri in _search_logged_model_uris(client, run_id, experiment_id):
        return uri

    for artifact_path in preferred_names:
        return f"runs:/{run_id}/{artifact_path}"

    raise RuntimeError(f"No MLflow model artifacts found for run {run_id}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--model-dir", help="Local model directory override")
    parser.add_argument("--stage", default="Approved")
    args = parser.parse_args()

    config, _ = load_configs()
    setup_mlflow(config)
    client = MlflowClient()
    model_name = config["mlflow"]["registered_model_name"]
    experiment = mlflow.get_experiment_by_name(config["mlflow"]["experiment_name"])
    if experiment is None:
        raise RuntimeError(f"Experiment not found: {config['mlflow']['experiment_name']}")

    try:
        client.create_registered_model(model_name)
    except Exception:
        pass

    model_uri = resolve_model_uri(client, args.run_id, experiment.experiment_id)
    last_error: Exception | None = None
    result = None
    for candidate in (
        model_uri,
        f"runs:/{args.run_id}/pytorch-model",
        f"runs:/{args.run_id}/model",
    ):
        if not candidate:
            continue
        try:
            result = mlflow.register_model(model_uri=candidate, name=model_name)
            model_uri = candidate
            break
        except mlflow.exceptions.MlflowException as exc:
            last_error = exc
    if result is None:
        raise last_error or RuntimeError(f"Failed to register model for run {args.run_id}")
    version = result.version
    client.set_registered_model_alias(model_name, "champion", version)
    if args.stage.lower() == "approved":
        client.set_model_version_tag(model_name, version, "stage", "Approved")
        client.set_model_version_tag(model_name, version, "framework", "PyTorch")
        client.set_model_version_tag(model_name, version, "architecture", "DistilBERT")
        client.set_model_version_tag(model_name, version, "classes", "12")

    if args.model_dir:
        src = Path(args.model_dir).resolve()
        export_dir = (ROOT / "artifacts" / "approved-model").resolve()
        if src != export_dir:
            if export_dir.exists():
                shutil.rmtree(export_dir)
            shutil.copytree(src, export_dir)

    print(
        json.dumps(
            {
                "registered_model": model_name,
                "version": version,
                "run_id": args.run_id,
                "model_uri": model_uri,
                "alias": "champion",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
