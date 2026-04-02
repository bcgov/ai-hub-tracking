from __future__ import annotations

from pathlib import Path

import pandas as pd
from azure.ai.evaluation._evaluate._evaluate import _validate_columns_for_target

from ai_hub_integration.evaluation import (
    ApimChatTarget,
    ChatEvaluationSettings,
    EvaluationThresholds,
    load_chat_evaluation_settings,
    load_chat_evaluation_suite,
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


class _FakeResponse:
    def raise_for_status(self) -> None:
        """Pretend the mocked target request completed successfully."""

    def json(self) -> dict[str, object]:
        """Return a minimal chat-completions style payload for target tests."""
        return {
            "choices": [{"message": {"content": "ok"}}],
            "model": "gpt-4.1-mini",
        }


class _FakeChatClient:
    def chat_completion_v1(self, tenant: str, model: str, query: str, max_tokens: int = 80) -> _FakeResponse:
        """Return a stubbed successful response for evaluation target tests."""
        return _FakeResponse()


def test_run_chat_evaluation_passes_model_config_to_similarity(monkeypatch, tmp_path: Path) -> None:
    """Verify that similarity evaluation receives the same model config as judge-based metrics."""
    captured: dict[str, dict[str, object]] = {}

    def fake_evaluate(**kwargs):
        """Capture per-evaluator calls and return a minimal successful result payload."""
        evaluator_name = next(iter(kwargs["evaluators"]))
        captured[evaluator_name] = kwargs
        return {
            "metrics": {f"{evaluator_name}.{evaluator_name}": 1.0},
            "_evaluation_summary": {
                evaluator_name: {
                    "status": "Completed",
                    "failed_lines": 0,
                    "error_message": None,
                }
            },
        }

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
    relevance_call = captured["relevance"]
    evaluators = {name: payload["evaluators"][name] for name, payload in captured.items()}
    column_mapping = relevance_call["evaluator_config"]["default"]["column_mapping"]

    assert result == {
        "profile_name": "custom",
        "metrics": {
            "coherence.coherence": 1.0,
            "f1_score.f1_score": 1.0,
            "fluency.fluency": 1.0,
            "relevance.relevance": 1.0,
            "similarity.similarity": 1.0,
        },
        "evaluator_failures": {},
        "_evaluation_summary": {
            "coherence": {"status": "Completed", "failed_lines": 0, "error_message": None},
            "f1_score": {"status": "Completed", "failed_lines": 0, "error_message": None},
            "fluency": {"status": "Completed", "failed_lines": 0, "error_message": None},
            "relevance": {"status": "Completed", "failed_lines": 0, "error_message": None},
            "similarity": {"status": "Completed", "failed_lines": 0, "error_message": None},
        },
    }
    assert evaluators["relevance"].args == (model_config,)
    assert evaluators["coherence"].args == (model_config,)
    assert evaluators["fluency"].args == (model_config,)
    assert evaluators["similarity"].args == (model_config,)
    assert evaluators["relevance"].kwargs == {"is_reasoning_model": True}
    assert evaluators["coherence"].kwargs == {"is_reasoning_model": True}
    assert evaluators["fluency"].kwargs == {"is_reasoning_model": True}
    assert evaluators["similarity"].kwargs == {"is_reasoning_model": True}
    assert evaluators["f1_score"].args == ()
    assert column_mapping == {
        "query": "${data.query}",
        "response": "${target.response}",
        "ground_truth": "${data.ground_truth}",
    }


def test_run_chat_evaluation_collects_evaluator_failures(monkeypatch, tmp_path: Path) -> None:
    """Verify that non-completed evaluator runs are surfaced to the caller."""

    def fake_evaluate(**kwargs):
        """Return one failed evaluator summary so the runner can surface it."""
        evaluator_name = next(iter(kwargs["evaluators"]))
        status = "Failed" if evaluator_name == "relevance" else "Completed"
        return {
            "metrics": {},
            "_evaluation_summary": {
                evaluator_name: {
                    "status": status,
                    "failed_lines": 1 if status == "Failed" else 0,
                    "error_message": "too many requests" if status == "Failed" else None,
                }
            },
        }

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

    assert result["evaluator_failures"] == {
        "relevance": {
            "status": "Failed",
            "failed_lines": 1,
            "error_message": "too many requests",
        }
    }


def test_run_chat_evaluation_retries_retryable_evaluator_error(monkeypatch, tmp_path: Path) -> None:
    """Verify that transient evaluator transport failures are retried before the run is failed."""
    attempts = {"similarity": 0}

    def fake_evaluate(**kwargs):
        """Fail the similarity evaluator once, then let all evaluators succeed."""
        evaluator_name = next(iter(kwargs["evaluators"]))
        if evaluator_name == "similarity" and attempts["similarity"] == 0:
            attempts["similarity"] += 1
            raise RuntimeError("APIConnectionError: Connection error.")
        return {
            "metrics": {f"{evaluator_name}.{evaluator_name}": 1.0},
            "_evaluation_summary": {
                evaluator_name: {
                    "status": "Completed",
                    "failed_lines": 0,
                    "error_message": None,
                }
            },
        }

    monkeypatch.setattr("ai_hub_integration.evaluation.RelevanceEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.CoherenceEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.FluencyEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.SimilarityEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.F1ScoreEvaluator", _FakeEvaluator)
    monkeypatch.setattr("ai_hub_integration.evaluation.evaluate", fake_evaluate)
    monkeypatch.setattr("ai_hub_integration.evaluation.time.sleep", lambda _: None)

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

    assert attempts["similarity"] == 1
    assert result["evaluator_failures"] == {}
    assert result["metrics"]["similarity.similarity"] == 1.0


def test_load_chat_evaluation_settings_disables_fluency_threshold_for_exact_profile(
    monkeypatch, tmp_path: Path
) -> None:
    """Verify that the exact-answer profile keeps fluency out of threshold enforcement."""
    monkeypatch.setenv("AI_EVAL_MIN_RELEVANCE", "4.0")
    monkeypatch.setenv("AI_EVAL_MIN_FLUENCY", "4.5")

    settings = load_chat_evaluation_settings(tmp_path, "ai-hub-admin", "gpt-4.1-mini")

    assert settings.profile_name == "exact"
    assert settings.enabled_metrics == ("relevance", "coherence", "similarity", "f1_score")
    assert settings.thresholds.relevance == 4.0
    assert settings.thresholds.fluency is None


def test_load_chat_evaluation_suite_adds_fluent_profile(monkeypatch, tmp_path: Path) -> None:
    """Verify that the suite loader returns both the exact and fluent datasets with profile-specific metrics."""
    monkeypatch.setenv("AI_EVAL_MIN_FLUENCY", "4.0")

    settings_list = load_chat_evaluation_suite(tmp_path, "ai-hub-admin", "gpt-4.1-mini")

    assert [settings.profile_name for settings in settings_list] == ["exact", "fluent"]
    assert settings_list[0].dataset_path == tmp_path / "eval_datasets" / "chat_quality.jsonl"
    assert settings_list[0].enabled_metrics == ("relevance", "coherence", "similarity", "f1_score")
    assert settings_list[1].dataset_path == tmp_path / "eval_datasets" / "chat_quality_fluent.jsonl"
    assert settings_list[1].enabled_metrics == ("relevance", "coherence", "fluency", "similarity")
    assert settings_list[1].thresholds.fluency == 4.0
    assert settings_list[1].thresholds.f1_score is None


def test_apim_chat_target_is_compatible_with_sdk_input_validation() -> None:
    """Verify that the SDK accepts the target callable when the dataset provides only the query column."""
    target = ApimChatTarget(_FakeChatClient(), "ai-hub-admin", "gpt-4.1-mini")

    _validate_columns_for_target(pd.DataFrame([{"query": "What is 2 + 2?"}]), target)


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
