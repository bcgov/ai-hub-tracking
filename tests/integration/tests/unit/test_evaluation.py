from __future__ import annotations

from pathlib import Path

from ai_hub_integration.evaluation import (
    ChatEvaluationSettings,
    EvaluationThresholds,
    run_chat_evaluation,
    validate_thresholds,
)


class _FakeEvaluator:
    def __init__(self, *args, **kwargs) -> None:
        """Capture constructor arguments so evaluator wiring can be asserted."""
        self.args = args
        self.kwargs = kwargs


class _FakeClient:
    pass


def test_run_chat_evaluation_passes_model_config_to_similarity(monkeypatch, tmp_path: Path) -> None:
    """Verify that similarity evaluation receives the same model config as judge-based metrics."""
    captured: dict[str, object] = {}

    def fake_evaluate(**kwargs):
        """Capture evaluation arguments and return a minimal metrics payload."""
        captured.update(kwargs)
        return {"metrics": {"similarity": 1.0}}

    monkeypatch.setattr("ai_hub_integration.evaluation.RelevanceEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.CoherenceEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.FluencyEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.SimilarityEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.F1ScoreEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.evaluate", fake_evaluate)

    settings = ChatEvaluationSettings(
        judge_endpoint="https://example.openai.azure.com",
        judge_api_key="secret",
        judge_deployment="gpt-5.1-chat",
        judge_api_version="2024-10-21",
        dataset_path=tmp_path / "chat_quality.jsonl",
        output_path=None,
        tenant="ai-hub-admin",
        model="gpt-4.1-mini",
        thresholds=EvaluationThresholds(),
    )

    result = run_chat_evaluation(_FakeClient(), settings)

    model_config = settings.model_config()
    evaluators = captured["evaluators"]

    assert result == {"metrics": {"similarity": 1.0}}
    assert evaluators["relevance"].args == (model_config,)
    assert evaluators["coherence"].args == (model_config,)
    assert evaluators["fluency"].args == (model_config,)
    assert evaluators["similarity"].args == (model_config,)
    assert evaluators["f1_score"].args == ()


def test_validate_thresholds_detects_metric_below_threshold() -> None:
    """Verify that threshold validation reports metrics that fall below the configured floor."""
    failures = validate_thresholds(
        {"relevance.relevance": 3.8, "coherence.coherence": 4.5},
        EvaluationThresholds(relevance=4.0, coherence=4.0),
    )

    assert failures == ["Metric relevance=3.800 is below threshold 4.000"]


def test_validate_thresholds_accepts_metrics_above_threshold() -> None:
    """Verify that threshold validation passes when all configured metrics clear the floor."""
    failures = validate_thresholds(
        {"relevance.relevance": 4.2, "coherence.coherence": 4.1},
        EvaluationThresholds(relevance=4.0, coherence=4.0),
    )

    assert failures == []
