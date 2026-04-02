# Integration Tests for AI Services Hub APIM

This directory is a Python project that hosts the live APIM/App Gateway integration suites and the optional Azure AI Evaluation runner.

## Tooling

- `uv` manages dependencies and local virtual environments.
- `pytest` runs the live integration suites under `tests/`.
- `requests` and the Azure SDKs power the APIM, Key Vault, and AI evaluation clients.

## Layout

| Path | Purpose |
|------|---------|
| `src/ai_hub_integration/config.py` | Loads environment config from env vars or terraform outputs |
| `src/ai_hub_integration/client.py` | Shared APIM/App Gateway/Document Intelligence client |
| `src/ai_hub_integration/evaluation.py` | Azure AI Evaluation SDK integration and threshold handling |
| `tests/test_*.py` | Live pytest suites |
| `tests/unit/` | Fast unit tests for shared helpers |
| `eval_datasets/chat_quality.jsonl` | Exact-answer dataset for concise instruction-following, extraction, normalization, and classification prompts |
| `eval_datasets/chat_quality_fluent.jsonl` | Fluent-response dataset for full-sentence explanations and summaries |
| `run-tests.py` | Pytest runner with suite aliases and direct/proxy grouping |
| `run-evaluation.py` | Standalone Azure AI Evaluation entrypoint |
| `run-tests.sh` | Shell wrapper around `run-tests.py` |

## Prerequisites

1. Install `uv` and Python 3.13.
2. Authenticate to Azure if you want Key Vault fallback or terraform-output discovery to work.
3. Ensure the target environment has already been deployed.

## Configuration

The harness resolves configuration in this order:

1. Explicit environment variables such as `APIM_GATEWAY_URL`, `AI_HUB_ADMIN_SUBSCRIPTION_KEY`, and `NRDAP_SUBSCRIPTION_KEY`
2. `infra-ai-hub/scripts/deploy-terraform.sh output <env>`
3. Direct `terraform output -json` as a fallback

Common variables:

```bash
export TEST_ENV=test
export APIM_GATEWAY_URL="https://your-gateway.example"
export AI_HUB_ADMIN_SUBSCRIPTION_KEY="..."
export NRDAP_SUBSCRIPTION_KEY="..."
export HTTPS_PROXY="http://127.0.0.1:8118"  # only for proxy-only suites
```

## Running Tests

```bash
cd tests/integration

# Install/update the local environment
uv sync --group dev

# Fast unit coverage
uv run pytest tests/unit -q

# All live suites
./run-tests.sh --env test --group all

# Direct suites only (public APIM/App Gateway paths)
./run-tests.sh --env test --group direct

# Proxy-only suites (Key Vault fallback / private endpoint access)
./run-tests.sh --env test --group proxy

# Run a specific suite alias
./run-tests.sh --env test tenant-info
./run-tests.sh --env test document-intelligence
```

## AI Evaluation

The optional evaluation runner uses `azure-ai-evaluation` to score two datasets by default:

- `eval_datasets/chat_quality.jsonl` keeps the deterministic exact-answer prompts and does not gate on fluency.
- `eval_datasets/chat_quality_fluent.jsonl` uses full-sentence prompts so fluency can be measured meaningfully.

This split avoids punishing the exact-answer suite for doing the right thing with terse outputs like `4`, `Victoria`, or `yes`, while still giving you a place to enforce fluent natural-language responses.

```bash
cd tests/integration

export AI_EVAL_JUDGE_ENDPOINT="https://<judge-endpoint>.openai.azure.com"
export AI_EVAL_JUDGE_API_KEY="..."
export AI_EVAL_JUDGE_DEPLOYMENT="gpt-4.1-mini"
export AI_EVAL_MIN_RELEVANCE="4.0"
export AI_EVAL_MIN_COHERENCE="4.0"
export AI_EVAL_MIN_FLUENCY="4.0"  # applied to the fluent-response dataset only

uv run python ./run-evaluation.py --env test
uv run pytest tests/test_ai_evaluation.py -q
```

Optional dataset overrides:

- `AI_EVAL_DATASET` overrides the exact-answer dataset path.
- `AI_EVAL_FLUENT_DATASET` overrides the fluent-response dataset path.

If the judge-model variables are not configured, the evaluation command and pytest suite skip cleanly.

## Suite Map

| Suite | Coverage |
|------|----------|
| `test_chat_completions.py` | Deployment-route chat completions for `ai-hub-admin` and NR-DAP |
| `test_v1_chat_completions.py` | OpenAI-compatible `/openai/v1` routing, streaming, and Bearer auth |
| `test_document_intelligence.py` | JSON and async Document Intelligence coverage |
| `test_document_intelligence_binary.py` | Binary and multipart Document Intelligence coverage through App Gateway |
| `test_app_gateway.py` | TLS, routing, auth normalization, and cross-key isolation |
| `test_tenant_info.py` | `/internal/tenant-info` contract coverage |
| `test_apim_key_rotation.py` | `/internal/apim-keys` and Key Vault fallback coverage |
| `test_mistral.py` | Mistral chat and OCR routing |
| `test_ai_evaluation.py` | Azure AI Evaluation dataset scoring |

## Validation

Run these checks before merging Python harness changes:

```bash
cd tests/integration
uv sync --group dev
uv run ruff check .
uv run ruff format --check .
uv run pytest tests/unit -q
```

Live suites depend on deployed infrastructure and valid subscription keys, so run the relevant groups that match your environment.