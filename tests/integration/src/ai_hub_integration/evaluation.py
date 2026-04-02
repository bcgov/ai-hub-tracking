from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from azure.ai.evaluation import (
    AzureOpenAIModelConfiguration,
    CoherenceEvaluator,
    F1ScoreEvaluator,
    FluencyEvaluator,
    RelevanceEvaluator,
    SimilarityEvaluator,
    evaluate,
)

from .client import ApimClient
from .config import uses_max_completion_tokens

EVALUATOR_MAX_ATTEMPTS = 3
EVALUATOR_RETRY_DELAY_SECONDS = 5
EXACT_EVALUATION_METRICS = ("relevance", "coherence", "similarity", "f1_score")
FLUENT_EVALUATION_METRICS = ("relevance", "coherence", "fluency", "similarity")


@dataclass(slots=True)
class EvaluationThresholds:
    relevance: float | None = None
    coherence: float | None = None
    fluency: float | None = None
    similarity: float | None = None
    f1_score: float | None = None

    @property
    def configured(self) -> bool:
        """Return whether at least one evaluation threshold has been set."""
        return any(value is not None for value in self.__dict__.values())


@dataclass(slots=True)
class ChatEvaluationSettings:
    judge_endpoint: str
    judge_api_key: str
    judge_deployment: str
    judge_api_version: str
    dataset_path: Path
    output_path: Path | None
    tenant: str
    model: str
    thresholds: EvaluationThresholds
    profile_name: str = "custom"
    enabled_metrics: tuple[str, ...] = ("relevance", "coherence", "fluency", "similarity", "f1_score")

    @property
    def configured(self) -> bool:
        """Return whether the required judge-model settings are populated."""
        return bool(self.judge_endpoint and self.judge_api_key and self.judge_deployment)

    def model_config(self) -> AzureOpenAIModelConfiguration:
        """Build the Azure AI Evaluation SDK model configuration for the judge."""
        return AzureOpenAIModelConfiguration(
            azure_endpoint=self.judge_endpoint,
            api_key=self.judge_api_key,
            azure_deployment=self.judge_deployment,
            api_version=self.judge_api_version,
        )


class ApimChatTarget:
    def __init__(self, client: ApimClient, tenant: str, model: str) -> None:
        """Bind the evaluation target to an APIM client, tenant, and model."""
        self.client = client
        self.tenant = tenant
        self.model = model

    def __call__(self, query: str, **kwargs: Any) -> dict[str, Any]:
        """Execute a single evaluation query against the hub target model."""
        response = self.client.chat_completion_v1(self.tenant, self.model, query, max_tokens=80)
        response.raise_for_status()
        payload = response.json()
        content = ((payload.get("choices") or [{}])[0].get("message") or {}).get("content", "")
        return {
            "response": content,
            "model": payload.get("model", self.model),
        }


def load_chat_evaluation_settings(tests_dir: Path, default_tenant: str, default_model: str) -> ChatEvaluationSettings:
    """Load the exact-answer evaluation profile from the environment."""
    common_settings = _common_chat_evaluation_kwargs(default_tenant, default_model)
    base_thresholds = _load_thresholds_from_env()

    return ChatEvaluationSettings(
        dataset_path=Path(os.getenv("AI_EVAL_DATASET", tests_dir / "eval_datasets" / "chat_quality.jsonl")),
        output_path=_load_output_path_from_env(),
        thresholds=_thresholds_for_metrics(base_thresholds, EXACT_EVALUATION_METRICS),
        profile_name="exact",
        enabled_metrics=EXACT_EVALUATION_METRICS,
        **common_settings,
    )


def load_chat_evaluation_suite(
    tests_dir: Path, default_tenant: str, default_model: str
) -> list[ChatEvaluationSettings]:
    """Load the exact-answer and fluent-response evaluation profiles."""
    exact_settings = load_chat_evaluation_settings(tests_dir, default_tenant, default_model)
    common_settings = _common_chat_evaluation_kwargs(default_tenant, default_model)
    base_thresholds = _load_thresholds_from_env()
    base_output_path = _load_output_path_from_env()

    fluent_settings = ChatEvaluationSettings(
        dataset_path=Path(
            os.getenv("AI_EVAL_FLUENT_DATASET", tests_dir / "eval_datasets" / "chat_quality_fluent.jsonl")
        ),
        output_path=_profile_output_path(base_output_path, "fluent"),
        thresholds=_thresholds_for_metrics(base_thresholds, FLUENT_EVALUATION_METRICS),
        profile_name="fluent",
        enabled_metrics=FLUENT_EVALUATION_METRICS,
        **common_settings,
    )

    return [exact_settings, fluent_settings]


def _optional_float(name: str) -> float | None:
    """Read an optional floating-point environment variable."""
    value = os.getenv(name)
    if value is None or value == "":
        return None
    return float(value)


def _common_chat_evaluation_kwargs(default_tenant: str, default_model: str) -> dict[str, Any]:
    """Load the judge-model and target-model values shared by every evaluation profile."""
    return {
        "judge_endpoint": os.getenv("AI_EVAL_JUDGE_ENDPOINT", ""),
        "judge_api_key": os.getenv("AI_EVAL_JUDGE_API_KEY", ""),
        "judge_deployment": os.getenv("AI_EVAL_JUDGE_DEPLOYMENT", ""),
        "judge_api_version": os.getenv("AI_EVAL_JUDGE_API_VERSION", "2024-10-21"),
        "tenant": os.getenv("AI_EVAL_TENANT", default_tenant),
        "model": os.getenv("AI_EVAL_MODEL", default_model),
    }


def _load_thresholds_from_env() -> EvaluationThresholds:
    """Read the configured metric thresholds from the environment."""
    return EvaluationThresholds(
        relevance=_optional_float("AI_EVAL_MIN_RELEVANCE"),
        coherence=_optional_float("AI_EVAL_MIN_COHERENCE"),
        fluency=_optional_float("AI_EVAL_MIN_FLUENCY"),
        similarity=_optional_float("AI_EVAL_MIN_SIMILARITY"),
        f1_score=_optional_float("AI_EVAL_MIN_F1_SCORE"),
    )


def _load_output_path_from_env() -> Path | None:
    """Read the optional evaluation output path from the environment."""
    output_path_env = os.getenv("AI_EVAL_OUTPUT_PATH")
    return Path(output_path_env) if output_path_env else None


def _thresholds_for_metrics(thresholds: EvaluationThresholds, enabled_metrics: tuple[str, ...]) -> EvaluationThresholds:
    """Return a threshold object with disabled metrics cleared for a profile."""
    enabled = set(enabled_metrics)
    return EvaluationThresholds(
        relevance=thresholds.relevance if "relevance" in enabled else None,
        coherence=thresholds.coherence if "coherence" in enabled else None,
        fluency=thresholds.fluency if "fluency" in enabled else None,
        similarity=thresholds.similarity if "similarity" in enabled else None,
        f1_score=thresholds.f1_score if "f1_score" in enabled else None,
    )


def _profile_output_path(base_output_path: Path | None, profile_name: str) -> Path | None:
    """Build a profile-specific output path when a suite run should emit multiple files."""
    if base_output_path is None:
        return None
    suffix = base_output_path.suffix or ".json"
    stem = base_output_path.stem if base_output_path.suffix else base_output_path.name
    return base_output_path.with_name(f"{stem}-{profile_name}{suffix}")


def _metric_value(metrics: dict[str, Any], exact_key: str, nested_suffix: str) -> float | None:
    """Extract a metric value from flattened Azure AI Evaluation metrics output."""
    for key, value in metrics.items():
        if key == exact_key or key.endswith(nested_suffix):
            try:
                return float(value)
            except (TypeError, ValueError):
                continue
    return None


def validate_thresholds(metrics: dict[str, Any], thresholds: EvaluationThresholds) -> list[str]:
    """Compare emitted metrics against configured thresholds and report failures."""
    expectations = {
        "relevance": (thresholds.relevance, "relevance", ".relevance"),
        "coherence": (thresholds.coherence, "coherence", ".coherence"),
        "fluency": (thresholds.fluency, "fluency", ".fluency"),
        "similarity": (thresholds.similarity, "similarity", ".similarity"),
        "f1_score": (thresholds.f1_score, "f1_score", ".f1_score"),
    }
    failures: list[str] = []
    for name, (threshold, exact_key, suffix) in expectations.items():
        if threshold is None:
            continue
        value = _metric_value(metrics, exact_key, suffix)
        if value is None:
            failures.append(f"Metric {name} was not present in evaluation output")
            continue
        if value < threshold:
            failures.append(f"Metric {name}={value:.3f} is below threshold {threshold:.3f}")
    return failures


def _column_mapping() -> dict[str, dict[str, dict[str, str]]]:
    """Return the SDK column mapping used for dataset-backed APIM chat evaluation."""
    return {
        "default": {
            "column_mapping": {
                "query": "${data.query}",
                "response": "${target.response}",
                "ground_truth": "${data.ground_truth}",
            }
        }
    }


def _collect_evaluator_failures(result: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Extract non-completed evaluator summaries from an Azure AI Evaluation result."""
    summary = result.get("_evaluation_summary")
    if not isinstance(summary, dict):
        return {}

    failures: dict[str, dict[str, Any]] = {}
    for evaluator_name, details in summary.items():
        if not isinstance(details, dict):
            continue
        if details.get("status") == "Completed":
            continue
        failures[evaluator_name] = {
            "status": details.get("status"),
            "failed_lines": details.get("failed_lines"),
            "error_message": details.get("error_message"),
        }
    return failures


def _is_retryable_evaluation_error(error: Exception) -> bool:
    """Return whether an evaluator failure appears to be transient and worth retrying."""
    message = str(error)
    retryable_fragments = (
        "APIConnectionError",
        "Connection error",
        "ReadError",
        "too_many_requests",
        "Too Many Requests",
        "Error code: 429",
    )
    return any(fragment in message for fragment in retryable_fragments)


def run_chat_evaluation(client: ApimClient, settings: ChatEvaluationSettings) -> dict[str, Any]:
    """Execute one dataset-backed Azure AI Evaluation profile against the APIM target."""
    model_config = settings.model_config()
    target = ApimChatTarget(client, settings.tenant, settings.model)
    judge_is_reasoning_model = uses_max_completion_tokens(settings.judge_deployment)
    all_evaluator_factories = {
        "relevance": lambda: RelevanceEvaluator(model_config, is_reasoning_model=judge_is_reasoning_model),
        "coherence": lambda: CoherenceEvaluator(model_config, is_reasoning_model=judge_is_reasoning_model),
        "fluency": lambda: FluencyEvaluator(model_config, is_reasoning_model=judge_is_reasoning_model),
        "similarity": lambda: SimilarityEvaluator(model_config, is_reasoning_model=judge_is_reasoning_model),
        "f1_score": F1ScoreEvaluator,
    }
    evaluator_factories = {name: all_evaluator_factories[name] for name in settings.enabled_metrics}

    aggregated_metrics: dict[str, Any] = {}
    aggregated_summary: dict[str, dict[str, Any]] = {}
    evaluator_failures: dict[str, dict[str, Any]] = {}

    for evaluator_name, factory in evaluator_factories.items():
        result: dict[str, Any] | None = None
        for attempt in range(1, EVALUATOR_MAX_ATTEMPTS + 1):
            try:
                result = evaluate(
                    data=str(settings.dataset_path),
                    target=target,
                    evaluators={evaluator_name: factory()},
                    evaluator_config=_column_mapping(),
                    output_path=None,
                    fail_on_evaluator_errors=True,
                )
                break
            except Exception as error:
                if attempt < EVALUATOR_MAX_ATTEMPTS and _is_retryable_evaluation_error(error):
                    time.sleep(EVALUATOR_RETRY_DELAY_SECONDS * attempt)
                    continue
                evaluator_failures[evaluator_name] = {
                    "status": "Failed",
                    "failed_lines": None,
                    "error_message": str(error),
                }
                break

        if result is None:
            continue

        aggregated_metrics.update(result.get("metrics", {}))
        summary = result.get("_evaluation_summary")
        if isinstance(summary, dict):
            aggregated_summary.update(summary)
        evaluator_failures.update(_collect_evaluator_failures(result))

    aggregated_result = {
        "profile_name": settings.profile_name,
        "metrics": aggregated_metrics,
        "evaluator_failures": evaluator_failures,
        "_evaluation_summary": aggregated_summary,
    }
    if settings.output_path:
        settings.output_path.write_text(json.dumps(aggregated_result, indent=2, sort_keys=True), encoding="utf-8")
    return aggregated_result


__all__ = [
    "ChatEvaluationSettings",
    "EvaluationThresholds",
    "load_chat_evaluation_settings",
    "load_chat_evaluation_suite",
    "run_chat_evaluation",
    "validate_thresholds",
]
