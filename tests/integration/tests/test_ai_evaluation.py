from __future__ import annotations

from pathlib import Path

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig
from ai_hub_integration.evaluation import load_chat_evaluation_suite, run_chat_evaluation, validate_thresholds

from .support import PRIMARY_TENANT, require_key

pytestmark = [pytest.mark.live, pytest.mark.ai_eval, pytest.mark.slow]


def test_chat_evaluation_suite_meets_configured_thresholds(
    client: ApimClient, integration_config: IntegrationConfig, tmp_path
) -> None:
    """Verify that the exact and fluent evaluation datasets meet their active thresholds."""
    require_key(integration_config, PRIMARY_TENANT)

    settings_list = load_chat_evaluation_suite(
        integration_config.tests_dir, PRIMARY_TENANT, integration_config.default_model
    )
    if not settings_list[0].configured:
        pytest.skip(
            "AI evaluation is not configured. "
            "Set AI_EVAL_JUDGE_ENDPOINT, AI_EVAL_JUDGE_API_KEY, "
            "and AI_EVAL_JUDGE_DEPLOYMENT."
        )

    for settings in settings_list:
        settings.output_path = tmp_path / f"chat-eval-{settings.profile_name}.json"
        result = run_chat_evaluation(client, settings)
        metrics = result.get("metrics", {})

        assert metrics, f"Expected evaluation metrics for {settings.profile_name}"
        assert result.get("evaluator_failures", {}) == {}
        assert validate_thresholds(metrics, settings.thresholds) == []
        assert Path(settings.output_path).exists()
