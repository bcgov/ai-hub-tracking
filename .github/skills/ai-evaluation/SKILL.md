---
name: ai-evaluation
description: Guidance for Azure AI Evaluation SDK usage in the Python integration harness for ai-hub-tracking.
---

# AI Evaluation Skills

Use this skill profile when creating, modifying, or debugging Azure AI Evaluation coverage in this repo.

## Use When
- Updating `tests/integration/src/ai_hub_integration/evaluation.py`
- Changing the judge-model configuration, thresholds, or dataset layout
- Modifying `run-evaluation.py` or the pytest `ai_eval` suite
- Adding new dataset-driven response quality checks for APIM-backed chat models

## Do Not Use When
- Working on generic APIM/App Gateway request coverage without evaluation scoring (use [Integration Testing](../integration-testing/SKILL.md))
- Researching external Foundry or Azure AI docs without repo changes (use [External Docs Research](../external-docs/SKILL.md))
- Changing backend model deployments or infrastructure provisioning only (use [IaC Coder](../iac-coder/SKILL.md))

## Input Contract
Required context before evaluation changes:
- Which tenant and deployed model should be scored
- Which judge model and endpoint will score the outputs
- Expected metrics and pass/fail thresholds
- Dataset source and whether `ground_truth` fields are available

## Output Contract
Every evaluation change should deliver:
- A dataset-backed evaluation flow under `tests/integration/`
- Clear env-var driven configuration for judge-model settings
- Threshold handling that fails only on configured metrics
- Documentation for any new datasets, thresholds, or workflow inputs
- Detailed docstrings on every Python function and method touched in the evaluation runtime, CLI, fixtures, and tests

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Scope
- Runtime module: `tests/integration/src/ai_hub_integration/evaluation.py`
- CLI entrypoint: `tests/integration/run-evaluation.py`
- Dataset directory: `tests/integration/eval_datasets/`
- Pytest coverage: `tests/integration/tests/test_ai_evaluation.py`
- Workflow step: `.github/workflows/.integration-tests-using-secure-tunnel.yml`

## Judge Configuration

The shared evaluation flow uses these environment variables:

- `AI_EVAL_JUDGE_ENDPOINT`
- `AI_EVAL_JUDGE_API_KEY`
- `AI_EVAL_JUDGE_DEPLOYMENT`
- `AI_EVAL_JUDGE_API_VERSION`
- `AI_EVAL_MIN_RELEVANCE`
- `AI_EVAL_MIN_COHERENCE`
- `AI_EVAL_MIN_FLUENCY`
- `AI_EVAL_MIN_SIMILARITY`
- `AI_EVAL_MIN_F1_SCORE`

If the required judge-model variables are missing, the CLI and pytest suite skip cleanly.

## Running Evaluation

```bash
cd tests/integration
uv sync --group dev

uv run python ./run-evaluation.py --env test
uv run pytest tests/test_ai_evaluation.py -q
```

## Change Checklist
1. Keep datasets in JSONL format with stable field names (`query`, `ground_truth`)
2. Reuse the shared APIM client target instead of direct SDK calls to deployed models
3. Add thresholds only for metrics you intend to gate on
4. Keep judge-model configuration env-driven; do not hardcode secrets or endpoints
5. Document any new dataset or threshold expectations in `tests/integration/README.md`
6. Add or update meaningful docstrings for every Python function or method changed in the evaluation files

## Validation Gates (Required)
1. `uv sync --group dev` succeeds in `tests/integration/`
2. `uv run ruff check .` is clean for the integration project
3. `uv run pytest tests/unit -q` passes
4. `uv run python ./run-evaluation.py --env <env>` skips cleanly when judge config is absent
5. When judge config is present, the evaluation output contains metrics and respects configured thresholds