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
    load_chat_evaluation_suite,
    run_chat_evaluation,
    validate_thresholds,
)


def parse_args() -> argparse.Namespace:
    """Parse command-line options for the standalone Azure AI evaluation runner."""
    parser = argparse.ArgumentParser(
        description="Run Azure AI Evaluation SDK checks against the deployed APIM endpoint"
    )
    parser.add_argument("-e", "--env", dest="environment", default=os.getenv("TEST_ENV", "test"))
    parser.add_argument("--dataset", default="")
    parser.add_argument("--tenant", default="")
    parser.add_argument("--model", default="")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def _output_path_for_profile(base_output: str, profile_name: str, *, single_profile: bool) -> Path:
    """Build a profile-specific output file path for suite runs."""
    output_path = Path(base_output)
    if single_profile:
        return output_path
    suffix = output_path.suffix or ".json"
    stem = output_path.stem if output_path.suffix else output_path.name
    return output_path.with_name(f"{stem}-{profile_name}{suffix}")


def main() -> int:
    """Execute the configured Azure AI Evaluation run and enforce thresholds."""
    args = parse_args()
    os.environ["TEST_ENV"] = args.environment

    config = IntegrationConfig.load(args.environment)
    if args.dataset:
        settings_list = [
            load_chat_evaluation_settings(config.tests_dir, config.apim_keys_tenant_1, config.default_model)
        ]
        settings_list[0].dataset_path = Path(args.dataset)
    else:
        settings_list = load_chat_evaluation_suite(config.tests_dir, config.apim_keys_tenant_1, config.default_model)

    for settings in settings_list:
        if args.output:
            settings.output_path = _output_path_for_profile(
                args.output,
                settings.profile_name,
                single_profile=len(settings_list) == 1,
            )
        if args.tenant:
            settings.tenant = args.tenant
        if args.model:
            settings.model = args.model

    if not settings_list[0].configured:
        print("AI evaluation skipped: set AI_EVAL_JUDGE_ENDPOINT, AI_EVAL_JUDGE_API_KEY, and AI_EVAL_JUDGE_DEPLOYMENT.")
        return 0

    client = ApimClient(config)
    failed = False
    for settings in settings_list:
        print(f"=== {settings.profile_name} evaluation ({settings.dataset_path.name}) ===")
        result = run_chat_evaluation(client, settings)
        metrics = result.get("metrics", {})
        print(json.dumps(metrics, indent=2, sort_keys=True))

        evaluator_failures = result.get("evaluator_failures", {})
        if evaluator_failures:
            print("\nAI evaluation reported evaluator failures:")
            for evaluator_name, details in evaluator_failures.items():
                message = details.get("error_message") or details.get("status") or "unknown failure"
                print(f"- {settings.profile_name}.{evaluator_name}: {message}")
            failed = True

        failures = validate_thresholds(metrics, settings.thresholds)
        if failures:
            print("\nAI evaluation thresholds failed:")
            for failure in failures:
                print(f"- {settings.profile_name}: {failure}")
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
