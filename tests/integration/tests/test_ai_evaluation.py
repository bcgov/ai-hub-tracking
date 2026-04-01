from __future__ import annotations

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig
from ai_hub_integration.evaluation import load_chat_evaluation_settings, run_chat_evaluation, validate_thresholds

from .support import PRIMARY_TENANT, require_key

pytestmark = [pytest.mark.live, pytest.mark.ai_eval, pytest.mark.slow]


def test_chat_quality_dataset_meets_configured_thresholds(
    client: ApimClient, integration_config: IntegrationConfig, tmp_path
) -> None:
    """Verify that the configured evaluation dataset meets all active thresholds."""
    require_key(integration_config, PRIMARY_TENANT)

    settings = load_chat_evaluation_settings(
        integration_config.tests_dir, PRIMARY_TENANT, integration_config.default_model
    )
    if not settings.configured:
        pytest.skip(
            "AI evaluation is not configured. "
            "Set AI_EVAL_JUDGE_ENDPOINT, AI_EVAL_JUDGE_API_KEY, "
            "and AI_EVAL_JUDGE_DEPLOYMENT."
        )

    settings.output_path = tmp_path / "chat-eval.json"
    result = run_chat_evaluation(client, settings)
    metrics = result.get("metrics", {})

    assert metrics, "Expected evaluation metrics"
    assert validate_thresholds(metrics, settings.thresholds) == []
