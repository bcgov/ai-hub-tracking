from __future__ import annotations

from ai_hub_integration.config import filter_chat_models, parse_stack_output


def test_filter_chat_models_excludes_embedding_and_codex() -> None:
    models = ["gpt-4.1-mini", "text-embedding-3-small", "codex-mini", "gpt-5-mini"]

    assert filter_chat_models(models) == ["gpt-4.1-mini", "gpt-5-mini"]


def test_parse_stack_output_strips_log_preamble() -> None:
    raw = '[INFO] loading\n{"appgw_url": {"value": "https://example"}}'

    parsed = parse_stack_output(raw)

    assert parsed["appgw_url"]["value"] == "https://example"
