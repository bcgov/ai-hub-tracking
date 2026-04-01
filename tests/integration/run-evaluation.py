from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
SRC_DIR = ROOT_DIR / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from ai_hub_integration import ApimClient, IntegrationConfig
from ai_hub_integration.evaluation import (
    load_chat_evaluation_settings,
    run_chat_evaluation,
    validate_thresholds,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Azure AI Evaluation SDK checks against the deployed APIM endpoint"
    )
    parser.add_argument("-e", "--env", dest="environment", default=os.getenv("TEST_ENV", "test"))
    parser.add_argument("--dataset", default="")
    parser.add_argument("--tenant", default="")
    parser.add_argument("--model", default="")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    os.environ["TEST_ENV"] = args.environment

    config = IntegrationConfig.load(args.environment)
    settings = load_chat_evaluation_settings(config.tests_dir, config.apim_keys_tenant_1, config.default_model)
    if args.dataset:
        settings.dataset_path = Path(args.dataset)
    if args.output:
        settings.output_path = Path(args.output)
    if args.tenant:
        settings.tenant = args.tenant
    if args.model:
        settings.model = args.model

    if not settings.configured:
        print("AI evaluation skipped: set AI_EVAL_JUDGE_ENDPOINT, AI_EVAL_JUDGE_API_KEY, and AI_EVAL_JUDGE_DEPLOYMENT.")
        return 0

    client = ApimClient(config)
    result = run_chat_evaluation(client, settings)
    metrics = result.get("metrics", {})
    print(json.dumps(metrics, indent=2, sort_keys=True))

    failures = validate_thresholds(metrics, settings.thresholds)
    if failures:
        print("\nAI evaluation thresholds failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
