#!/usr/bin/env python3
"""Upload e execução do pipeline Banking77 no Kubeflow Pipelines (OpenShift AI)."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

import kfp
from kfp import dsl


def _oc_token(namespace: str = "customer-intent-demo") -> str:
    try:
        return subprocess.check_output(["oc", "whoami", "-t"], text=True).strip()
    except subprocess.CalledProcessError:
        return subprocess.check_output(
            [
                "oc",
                "create",
                "token",
                "customer-intent-pipeline",
                "-n",
                namespace,
                "--duration=24h",
            ],
            text=True,
        ).strip()


def _wait_run(client: kfp.Client, run_id: str, timeout_sec: int = 7200) -> str:
    deadline = time.time() + timeout_sec
    last = ""
    while time.time() < deadline:
        run = client.get_run(run_id)
        status = run.run.status if run.run else "Unknown"
        if status != last:
            print(f"Run {run_id}: {status}", flush=True)
            last = status
        if status in {"Succeeded", "Failed", "Error", "Skipped"}:
            return status
        time.sleep(30)
    return last


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--namespace", default="customer-intent-demo")
    parser.add_argument("--host", required=True)
    parser.add_argument("--pipeline-yaml", type=Path, required=True)
    parser.add_argument("--run-name", required=True)
    parser.add_argument("--service-account", default="customer-intent-pipeline")
    parser.add_argument("--wait", action="store_true", default=True)
    parser.add_argument("--no-wait", dest="wait", action="store_false")
    parser.add_argument("--timeout", type=int, default=7200)
    args = parser.parse_args()

    token = _oc_token(args.namespace)
    client = kfp.Client(
        host=args.host,
        existing_token=token,
        namespace=args.namespace,
        verify_ssl=False,
    )

    exp_name = "customer-intent-banking77"
    try:
        experiment = client.create_experiment(
            name=exp_name,
            description="Treino Banking77 customer intent demo",
            namespace=args.namespace,
        )
    except Exception:
        experiment = client.get_experiment(
            experiment_name=exp_name,
            namespace=args.namespace,
        )
    experiment_id = experiment.experiment_id or experiment.id

    print(f"Experiment: {experiment_id}", flush=True)

    try:
        pipeline = client.upload_pipeline(
            pipeline_package_path=str(args.pipeline_yaml),
            pipeline_name="banking77-customer-intent-training",
            description="Banking77: baseline + 3x DistilBERT + MLflow",
        )
        pipeline_id = pipeline.pipeline_id or pipeline.id
        print(f"Pipeline uploaded: {pipeline_id}", flush=True)
    except Exception as exc:
        print(f"Aviso: upload pipeline falhou ({exc}); executando do YAML local.", flush=True)

    run = client.run_pipeline(
        experiment_id=experiment_id,
        job_name=args.run_name,
        pipeline_package_path=str(args.pipeline_yaml),
        params={},
        service_account=args.service_account,
    )
    run_id = run.run_id or run.id
    print(f"Pipeline run started: {run_id}", flush=True)
    print(
        f"Dashboard: {args.host}/#/runs/details/{run_id}",
        flush=True,
    )

    if args.wait:
        final = _wait_run(client, run_id, timeout_sec=args.timeout)
        print(f"Final status: {final}", flush=True)
        return 0 if final == "Succeeded" else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
