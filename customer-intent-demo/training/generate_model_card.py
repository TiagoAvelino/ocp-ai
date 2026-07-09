#!/usr/bin/env python3
"""Gera model-card.md para o run aprovado."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from common import ROOT, load_configs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output", default=str(ROOT / "artifacts" / "approved-model" / "model-card.md"))
    args = parser.parse_args()

    config, intent_cfg = load_configs()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    content = f"""# Banking77 Customer Intent Classifier

- **Model**: DistilBERT fine-tuned
- **Classes**: {len(intent_cfg['selected_intents'])}
- **Dataset**: {config['dataset']['name']}
- **License**: {intent_cfg['license']}
- **MLflow run**: {args.run_id}
- **Threshold default**: {config['default_threshold']}

## Selected intents

{chr(10).join('- ' + intent for intent in intent_cfg['selected_intents'])}

## Business routing

The model returns intent + confidence. Quarkus applies AUTO_ROUTE or HUMAN_REVIEW.
"""
    output.write_text(content, encoding="utf-8")
    print(json.dumps({"model_card": str(output)}, indent=2))


if __name__ == "__main__":
    main()
