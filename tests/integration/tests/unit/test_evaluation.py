from __future__ import annotations

from ai_hub_integration.evaluation import EvaluationThresholds, validate_thresholds


def test_validate_thresholds_detects_metric_below_threshold() -> None:
    failures = validate_thresholds(
        {"relevance.relevance": 3.8, "coherence.coherence": 4.5},
        EvaluationThresholds(relevance=4.0, coherence=4.0),
    )

    assert failures == ["Metric relevance=3.800 is below threshold 4.000"]


def test_validate_thresholds_accepts_metrics_above_threshold() -> None:
    failures = validate_thresholds(
        {"relevance.relevance": 4.2, "coherence.coherence": 4.1},
        EvaluationThresholds(relevance=4.0, coherence=4.0),
    )

    assert failures == []
