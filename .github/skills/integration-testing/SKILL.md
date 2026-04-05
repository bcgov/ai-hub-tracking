---
name: integration-testing
description: Guidance for writing and running Python/pytest integration tests against APIM, App Gateway, and AI services in ai-hub-tracking.
---

# Integration Testing Skills

Use this skill profile when creating, modifying, or debugging integration tests in this repo.

## Use When
- Writing new pytest suites under `tests/integration/tests/`
- Modifying the shared integration runtime in `tests/integration/src/ai_hub_integration/`
- Debugging CI or local failures in the secure-tunnel integration workflow
- Extending `run-tests.py`, `run-tests.sh`, or suite alias/group behavior

## Do Not Use When
- Changing APIM policy behavior without updating tests (use [API Management](../api-management/SKILL.md) first, then come here)
- Modifying Terraform infrastructure without touching test execution or assertions (use [IaC Coder](../iac-coder/SKILL.md))
- Working on Azure AI Evaluation scoring logic only (use [AI Evaluation](../ai-evaluation/SKILL.md))

## Input Contract
Required context before making test changes:
- Which tenant(s), API paths, and backend behaviors are under test
- Whether the scenario requires App Gateway, Key Vault fallback, or the secure tunnel
- Any feature flags that gate the behavior (`document_intelligence_enabled`, key rotation, tenant capabilities)

## Output Contract
Every test change should deliver:
- Pytest functions with explicit, behavior-focused names
- Detailed docstrings on every Python function, method, fixture, helper, and test touched by the change; missing function documentation is not acceptable in `tests/integration/`
- Proper skip guards for missing keys, App Gateway absence, or disabled features
- Coverage built on the shared Python runtime instead of ad hoc curl/bash logic
- No hardcoded URLs, keys, or model names outside the centralized config/runtime layer

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Documentation Sync
- If the change adds, removes, renames, or materially reorganizes tracked files or directories, update the root `README.md` `Folder Structure` section in the same change. Do not add gitignored or local-only artifacts to that tree.
- Review the documentation sync matrix in [../../copilot-instructions.md](../../copilot-instructions.md) and update any area-specific README or docs pages it calls out for the touched subtree.

## Scope
- Test framework: **pytest**
- Project root: `tests/integration/`
- Runtime modules: `src/ai_hub_integration/config.py`, `client.py`, `runner.py`
- Live suites: `tests/test_*.py`
- Unit tests: `tests/unit/`
- CLI entrypoints: `run-tests.py`, `run-tests.sh`
- Optional evaluation CLI: `run-evaluation.py`

## Suite Inventory

| File | Focus |
|---|---|
| `tests/test_chat_completions.py` | OpenAI deployment-route coverage centered on `ai-hub-admin` with NR-DAP smoke checks |
| `tests/test_v1_chat_completions.py` | OpenAI `/openai/v1` format, streaming SSE, Bearer auth, and rate-limit regression checks |
| `tests/test_document_intelligence.py` | JSON and async Document Intelligence coverage centered on `ai-hub-admin` |
| `tests/test_document_intelligence_binary.py` | WAF/App Gateway allow-rules for binary and multipart Document Intelligence uploads |
| `tests/test_app_gateway.py` | App Gateway TLS, routing, auth normalization, and the retained cross-key verification |
| `tests/test_apim_key_rotation.py` | `/internal/apim-keys` endpoint, rotation metadata, and Key Vault fallback coverage |
| `tests/test_tenant_info.py` | Tenant info endpoint, model metadata, and service feature flags for `ai-hub-admin` |
| `tests/test_mistral.py` | Mistral chat and OCR routing via APIM |
| `tests/test_ai_evaluation.py` | Optional Azure AI Evaluation SDK scoring |

## Execution Model

`run-tests.py` is the authoritative runner. It provides:

- Suite alias mapping from legacy names (`chat-completions`, `apim-key-rotation`, etc.)
- Marker-based grouping: `all`, `direct`, `proxy`
- Optional inclusion of `ai_eval` suites

The shell wrapper `run-tests.sh` exists for convenience and backwards-compatible local usage, but it delegates to `run-tests.py`.

## Running Tests

```bash
cd tests/integration
uv sync --group dev

# Unit tests for shared logic
uv run pytest tests/unit -q

# All live suites
uv run python ./run-tests.py --env test --group all

# Direct-only suites
uv run python ./run-tests.py --env test --group direct

# Proxy-only suites
HTTP_PROXY=http://127.0.0.1:8118 \
HTTPS_PROXY=http://127.0.0.1:8118 \
uv run python ./run-tests.py --env test --group proxy
```

## Skip Patterns

| Pattern | When to use |
|---|---|
| `require_key(config, tenant)` | Test requires a tenant subscription key |
| `require_appgw(config)` | Test requires App Gateway to be deployed |
| `integration_config.is_apim_key_rotation_enabled()` | Key-rotation endpoint can be disabled per environment |
| `pytest.skip(...)` | Inline skip for unavailable infrastructure or optional evaluation config |

## CI Model

`.github/workflows/.integration-tests-using-secure-tunnel.yml` splits execution into:

1. **Direct**: `uv run python ./run-tests.py --group direct`
2. **Optional AI Evaluation**: `uv run python ./run-evaluation.py` when judge-model secrets and vars exist
3. **Proxy**: `uv run python ./run-tests.py --group proxy` with `HTTP_PROXY`/`HTTPS_PROXY` set to the chisel+privoxy tunnel

## Validation Gates (Required)
1. `uv sync --group dev` succeeds
2. `uv run ruff check .` is clean
3. `uv run ruff format --check .` is clean
4. `uv run pytest tests/unit -q` passes
5. Live tests keep retry-safe behavior for 429/503-prone endpoints
6. Async Document Intelligence flows still poll through `wait_for_operation`
7. Every Python function and method in the touched integration files has a meaningful docstring before handoff

## Detailed References

For helper signatures, config loading rules, retry behavior, secure-tunnel expectations, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).