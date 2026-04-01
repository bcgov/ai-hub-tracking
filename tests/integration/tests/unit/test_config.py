from __future__ import annotations

from ai_hub_integration.config import filter_chat_models, filter_deployments_chat_models, parse_stack_output


def test_filter_chat_models_keeps_openai_and_v1_mistral_models() -> None:
    models = [
        "gpt-4.1-mini",
        "text-embedding-3-small",
        "cohere-command-a",
        "Cohere-rerank-v4.0-pro",
        "Mistral-Large-3",
        "mistral-document-ai-2505",
        "gpt-5-mini",
    ]

    assert filter_chat_models(models) == ["gpt-4.1-mini", "Mistral-Large-3", "gpt-5-mini"]


def test_filter_deployments_chat_models_keeps_openai_route_models_only() -> None:
    models = ["gpt-4.1-mini", "Mistral-Large-3", "o3-mini", "cohere-command-a", "mistral-document-ai-2505"]

    assert filter_deployments_chat_models(models) == ["gpt-4.1-mini", "o3-mini"]


def test_parse_stack_output_strips_log_preamble() -> None:
    raw = '[INFO] loading\n{"appgw_url": {"value": "https://example"}}'

    parsed = parse_stack_output(raw)

    assert parsed["appgw_url"]["value"] == "https://example"
