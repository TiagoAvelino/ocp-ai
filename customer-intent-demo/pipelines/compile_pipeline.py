#!/usr/bin/env python3
"""Compila o pipeline Kubeflow para YAML (importável no OpenShift AI)."""

from __future__ import annotations

from pathlib import Path

from kfp import compiler

from banking77_training_pipeline import banking77_customer_intent_training

OUTPUT = Path(__file__).resolve().parent / "banking77-customer-intent-pipeline.yaml"


def main() -> None:
    compiler.Compiler().compile(
        pipeline_func=banking77_customer_intent_training,
        package_path=str(OUTPUT),
    )
    import shutil

    import_name = OUTPUT.parent / "banking77-customer-intent-training.pipeline.yaml"
    shutil.copy(OUTPUT, import_name)
    print(f"Pipeline compilado: {OUTPUT}")
    print(f"Import OpenShift AI: {import_name}")


if __name__ == "__main__":
    main()
