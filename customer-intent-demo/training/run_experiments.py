#!/usr/bin/env python3
"""Executa pipeline completo de experimentos na ordem recomendada."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    cmd = [sys.executable, str(ROOT / "training" / "run_mlflow_banking_experiment.py"), *sys.argv[1:]]
    subprocess.run(cmd, check=True, cwd=ROOT)


if __name__ == "__main__":
    main()
