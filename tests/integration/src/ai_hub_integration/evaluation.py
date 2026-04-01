from __future__ import annotations

import os
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


@dataclass(slots=True)
class EvaluationThresholds:
    relevance: float | None = None
    coherence: float | None = None
    fluency: float | None = None
    similarity: float | None = None
    f1_score: float | None = None

    @property
    def configured(self) -> bool:
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

    @property
    def configured(self) -> bool:
        return bool(self.judge_endpoint and self.judge_api_key and self.judge_deployment)

    def model_config(self) -> AzureOpenAIModelConfiguration:
        return AzureOpenAIModelConfiguration(
            azure_endpoint=self.judge_endpoint,
            api_key=self.judge_api_key,
            azure_deployment=self.judge_deployment,
            api_version=self.judge_api_version,
        )


class ApimChatTarget:
    def __init__(self, client: ApimClient, tenant: str, model: str) -> None:
        self.client = client
        self.tenant = tenant
        self.model = model

    def __call__(self, query: str, **_: Any) -> dict[str, Any]:
        response = self.client.chat_completion_v1(self.tenant, self.model, query, max_tokens=80)
        response.raise_for_status()
        payload = response.json()
        content = ((payload.get("choices") or [{}])[0].get("message") or {}).get("content", "")
        return {
            "response": content,
            "model": payload.get("model", self.model),
        }


def load_chat_evaluation_settings(tests_dir: Path, default_tenant: str, default_model: str) -> ChatEvaluationSettings:
    thresholds = EvaluationThresholds(
        relevance=_optional_float("AI_EVAL_MIN_RELEVANCE"),
        coherence=_optional_float("AI_EVAL_MIN_COHERENCE"),
        fluency=_optional_float("AI_EVAL_MIN_FLUENCY"),
        similarity=_optional_float("AI_EVAL_MIN_SIMILARITY"),
        f1_score=_optional_float("AI_EVAL_MIN_F1_SCORE"),
    )

    dataset = Path(os.getenv("AI_EVAL_DATASET", tests_dir / "eval_datasets" / "chat_quality.jsonl"))
    output_path_env = os.getenv("AI_EVAL_OUTPUT_PATH")
    output_path = Path(output_path_env) if output_path_env else None

    return ChatEvaluationSettings(
        judge_endpoint=os.getenv("AI_EVAL_JUDGE_ENDPOINT", ""),
        judge_api_key=os.getenv("AI_EVAL_JUDGE_API_KEY", ""),
        judge_deployment=os.getenv("AI_EVAL_JUDGE_DEPLOYMENT", ""),
        judge_api_version=os.getenv("AI_EVAL_JUDGE_API_VERSION", "2024-10-21"),
        dataset_path=dataset,
        output_path=output_path,
        tenant=os.getenv("AI_EVAL_TENANT", default_tenant),
        model=os.getenv("AI_EVAL_MODEL", default_model),
        thresholds=thresholds,
    )


def _optional_float(name: str) -> float | None:
    value = os.getenv(name)
    if value is None or value == "":
        return None
    return float(value)


def _metric_value(metrics: dict[str, Any], exact_key: str, nested_suffix: str) -> float | None:
    for key, value in metrics.items():
        if key == exact_key or key.endswith(nested_suffix):
            try:
                return float(value)
            except (TypeError, ValueError):
                continue
    return None


def validate_thresholds(metrics: dict[str, Any], thresholds: EvaluationThresholds) -> list[str]:
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


def run_chat_evaluation(client: ApimClient, settings: ChatEvaluationSettings) -> dict[str, Any]:
    model_config = settings.model_config()
    target = ApimChatTarget(client, settings.tenant, settings.model)
    evaluators = {
        "relevance": RelevanceEvaluator(model_config),
        "coherence": CoherenceEvaluator(model_config),
        "fluency": FluencyEvaluator(model_config),
        "similarity": SimilarityEvaluator(),
        "f1_score": F1ScoreEvaluator(),
    }

    return evaluate(
        data=str(settings.dataset_path),
        target=target,
        evaluators=evaluators,
        evaluator_config={
            "default": {
                "column_mapping": {
                    "query": "${data.query}",
                    "response": "${outputs.response}",
                    "ground_truth": "${data.ground_truth}",
                }
            }
        },
        output_path=str(settings.output_path) if settings.output_path else None,
    )


__all__ = [
    "ChatEvaluationSettings",
    "EvaluationThresholds",
    "load_chat_evaluation_settings",
    "run_chat_evaluation",
    "validate_thresholds",
]
