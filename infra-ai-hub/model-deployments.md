# Model Deployments & Quota Allocation

> **IMPORTANT:** This file must be updated whenever tenants are added, removed, or their model deployments are modified.
> See [IaC Coder Skills](../.github/skills/iac-coder/SKILL.md) for the mandatory update rule.

This document tracks model capacity allocated to each tenant across all environments. The hub supports two AI backend pathways:

- **Azure AI Foundry** — Managed OpenAI and third-party models; capacity in TPM or PTU. Foundry tenants share a regional quota pool.
- **vLLM (open-source)** — GPU-backed Container App running open-source models (e.g. Gemma 4 31B). Shared GPU infrastructure per environment; no regional quota — capacity is bounded by the GPU workload profile. Tenants opt in via `vllm = { enabled = true, models = [{model_id = "...", tokens_per_minute = N}] }` in `tenant.tfvars`. `tokens_per_minute` is per-model and defaults to the tenant's `rate_limiting.tokens_per_minute` when omitted.

Both pathways use the same APIM base URL (`{apim}/{tenant}/openai/v1`). The `model=` field in the request body selects the backend — no URL change required.

### vLLM Cold-Start Warning

`min_replicas = 0` (scale-to-zero) is the default for the vllm stack to control GPU cost. Gemma 4 31B cold start is **5–10 minutes**. Tenants that need lower first-token latency should request `min_replicas = 1` from the platform operator, but that only keeps one replica warm. It does not add zone redundancy or change the current vLLM deployment topology: the stack still creates a non-zone-redundant Container Apps environment (`modules/vllm-service/main.tf`) and Azure's Container Apps reliability guidance requires at least two replicas in a zone-redundant environment to spread traffic across availability zones. The published Azure Container Apps service-level commitment remains **99.95%**. Sources: [Azure Container Apps SLA](https://azure.microsoft.com/en-us/support/legal/sla/container-apps/v1_0/), [Microsoft Licensing SLA index](https://www.microsoft.com/licensing/docs/view/service-level-agreements-sla-for-online-services?lang=1), and [Reliability in Azure Container Apps](https://learn.microsoft.com/en-us/azure/reliability/reliability-azure-container-apps#requirements).

## vLLM Model Catalogue

The vLLM stack serves **one model per hub environment**. The operator selects the model in
`params/{env}/shared.tfvars`. When the model changes, all tenant `vllm.models[*].model_id`
values must be updated to match — the `check "vllm_model_id_matches_deployed_model"` block
will warn at plan time if they diverge.

> **Memory note:** VRAM budget at `gpu_memory_utilization = 0.9` on an A100 80 GB GPU is
> **72 GB**. BF16 weight size ≈ `params_B × 2 GB`. The remainder is available for KV cache
> and CUDA runtime overhead. Larger models (≥ 30 B BF16) leave little KV headroom on a
> single A100 — use a pre-quantized AWQ variant unless the model fits comfortably.

| Model | HF ID | Licence | BF16 weight | Effective KV budget | `max_model_len` | `quantization` | HF token | Cold start |
|---|---|---|---|---|---|---|---|---|
| **Phi-4** | `microsoft/phi-4` | MIT | ~28 GB | ~44 GB | 32 768 | — | No | ~2–3 min |
| **Qwen3-32B (AWQ)** | `Qwen/Qwen3-32B-AWQ` | Apache 2.0 | ~16 GB (INT4) | ~56 GB | 32 768 | `awq` | No | ~5–8 min |
| **Gemma 4 31B-it** | `google/gemma-4-31B-it` | Gemma ToU | ~62 GB | ~10 GB ¹ | 32 768 | — | Yes (gated) | ~5–10 min |

> ¹ Tight KV headroom; suitable for low-concurrency workloads. Model requires the `aca_proxy.py`
> SSE streaming workaround — handled automatically by the module when `model_id` contains `gemma-4`.
>
> **Qwen3-32B-AWQ:** Verify the HF repo is available before deploying:
> `https://huggingface.co/Qwen/Qwen3-32B-AWQ`. The tenant `vllm.models[*].model_id` must
> be set to `Qwen/Qwen3-32B-AWQ` (the AWQ repo), not `Qwen/Qwen3-32B`.

## Regional Quota Limits (Canada East)

These are the maximum TPM quotas available per model across the entire subscription.
All models listed are available via GlobalStandard SKU without explicit access approval.

| Model | Kind | Quota Limit (TPM) |
|-------|------|------------------:|
| gpt-4.1 | Chat | 30,000 |
| gpt-4.1-mini | Chat | 150,000 |
| gpt-4.1-nano | Chat | 150,000 |
| gpt-4o | Chat | 30,000 |
| gpt-4o-mini | Chat | 150,000 |
| gpt-5-mini | Chat | 10,000 |
| gpt-5-nano | Chat | 150,000 |
| gpt-5.1-chat | Chat (Preview) | 5,000 |
| gpt-5.1-codex-mini | Code | 10,000 |
| o1 | Reasoning | 5,000 |
| o3-mini | Reasoning | 5,000 |
| o4-mini | Reasoning | 10,000 |
| text-embedding-ada-002 | Embedding | 10,000 |
| text-embedding-3-large | Embedding | 10,000 |
| text-embedding-3-small | Embedding | 10,000 |

### Cohere Models (Canada East)

| Model | Kind | Quota Limit |
|-------|------|------------:|
| cohere-command-a | Chat | 1,000 |
| Cohere-command-r | Chat | not tracked |
| Cohere-command-r-08-2024 | Chat | not tracked |
| Cohere-command-r-plus | Chat | not tracked |
| Cohere-command-r-plus-08-2024 | Chat | not tracked |
| Cohere-embed-v3-english | Embedding | not tracked |
| Cohere-embed-v3-multilingual | Embedding | not tracked |
| Cohere-rerank-v4.0-pro | Rerank | 3,000 |
| Cohere-rerank-v4.0-fast | Rerank | 3,000 |

### Mistral Models (Canada East)

Mistral models are serverless MaaS (pay-per-token). The Foundry deployment UI reports a 10M TPM total quota for `Mistral-Large-3`; the document AI models do not yet have an agreed shared allocation target in this repo.

| Model | Kind | Quota Limit |
|-------|------|------------:|
| Mistral-Large-3 | Chat / Vision | 10,000 |
| mistral-document-ai-2505 | Document AI | not documented |
| mistral-document-ai-2512 | Document AI | not documented |

---

## TEST Environment

Quota allocation strategy: **1% per tenant** for all models.

The table below covers the quota-based **GlobalStandard** deployments. Provisioned deployments are listed separately because their capacity is measured in PTU, not k TPM.

| Model | Quota Limit | wlrs (1%) | sdpr (1%) | nr-dap (1%) | gcpe (1%) | ai-hub-admin (1%) | Total (5%) | Remaining |
|-------|------------:|----------:|----------:|------------:|----------:|------------------:|-----------:|----------:|
| gpt-4.1 | 30,000 | 300 | 300 | 300 | 300 | 300 | 1,500 (5%) | 28,500 |
| gpt-4.1-mini | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 1,500 | 7,500 (5%) | 142,500 |
| gpt-4.1-nano | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 1,500 | 7,500 (5%) | 142,500 |
| gpt-4o | 30,000 | 300 | 300 | 300 | 300 | 300 | 1,500 (5%) | 28,500 |
| gpt-4o-mini | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 1,500 | 7,500 (5%) | 142,500 |
| gpt-5-mini | 10,000 | 100 | 100 | 100 | 100 | 100 | 500 (5%) | 9,500 |
| gpt-5-nano | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 1,500 | 7,500 (5%) | 142,500 |
| gpt-5.1-chat | 5,000 | 50 | 50 | 50 | 50 | 50 ¹ | 250 (5%) | 4,750 |
| gpt-5.1-codex-mini | 10,000 | 100 | 100 | 100 | 100 | 100 | 500 (5%) | 9,500 |
| o1 | 5,000 | 50 | 50 | 50 | 50 | 50 | 250 (5%) | 4,750 |
| o3-mini | 5,000 | 50 | 50 | 50 | 50 | 50 | 250 (5%) | 4,750 |
| o4-mini | 10,000 | 100 | 100 | 100 | 100 | 100 | 500 (5%) | 9,500 |
| text-embedding-ada-002 | 10,000 | 100 | 100 | 100 | 100 | 100 | 500 (5%) | 9,500 |
| text-embedding-3-large | 10,000 | 100 | 100 | 100 | 100 | 100 | 500 (5%) | 9,500 |
| text-embedding-3-small | 10,000 | 100 | 100 | 100 | 100 | 100 | 500 (5%) | 9,500 |

### TEST Provisioned Deployments

| Tenant | Deployment | Model | Scale Type | Capacity | Input TPM per PTU | Output Weight | Effective input-equivalent TPM | Raw fallback TPM |
|-------|------------|-------|------------|---------:|------------------:|--------------:|-------------------------------:|-----------------:|
| wlrs | gpt-5.1 | gpt-5.1 | GlobalProvisionedManaged | 15 PTU | 4,750 | 8x | 71,250 | 8,906 |

The raw fallback cap is still calculated as `floor(input_equivalent_tokens_per_minute / output_tokens_to_input_ratio)`.
For GPT-5.1, APIM now enforces non-streaming traffic with response-weighted actual usage on a dedicated PTU backend using `prompt_tokens * 1 + completion_tokens * 8` against the `71,250` weighted TPM budget. The `8,906` raw TPM value remains published as a fallback ceiling for streaming requests, where APIM cannot reliably read final SSE usage before the stream is returned.

### Cohere Models (ai-hub-admin only)

The following 6 models were tested and excluded:
- `Cohere-command-r`, `Cohere-command-r-plus` — **deprecated** (`ServiceModelDeprecated` since 06/30/2025)
- `Cohere-command-r-08-2024`, `Cohere-command-r-plus-08-2024`, `Cohere-embed-v3-english`, `Cohere-embed-v3-multilingual` — **not in BC Gov Private Marketplace** (`UserError`)

| Model | Quota Limit | ai-hub-admin |
|-------|------------:|-------------:|
| cohere-command-a | 1,000 | 10 |
| Cohere-rerank-v4.0-pro | 3,000 | 30 |
| Cohere-rerank-v4.0-fast | 3,000 | 30 |

### Mistral Models (ai-hub-admin only)

The following 4 models were tested and excluded:
- `mistral-medium-2505`, `mistral-small-2503`, `Codestral-2501` — **not in BC Gov Private Marketplace** (`Error`)
- `mistral-ocr-2503` — **not supported** (`DeploymentModelNotSupported`)

3 Mistral models are serverless MaaS (pay-per-token). Based on the Foundry deployment settings, `Mistral-Large-3` has a 10M TPM total quota and `ai-hub-admin` now reserves 1% of that total. The document AI models remain at the minimal allocation until a separate quota target is defined.

| Model | Kind | Quota Limit | ai-hub-admin |
|-------|------|------------:|-------------:|
| Mistral-Large-3 | Chat / Vision | 10,000 | 100 |
| mistral-document-ai-2505 | Document AI | not documented | 1 |
| mistral-document-ai-2512 | Document AI | not documented | 1 |

> ¹ `ai-hub-admin / gpt-5.1-chat` uses a custom content filter policy (`ai-hub-admin-gpt-5.1-chat-filter`). See [Content Filters](#content-filters-rai-policies) below.

---

## DEV Environment

Quota allocation strategy: **1% per tenant** for all models.

| Model | Quota Limit | wlrs (1%) | sdpr (1%) | nr-dap (1%) | gcpe (1%) | Total (4%) | Remaining |
|-------|------------:|----------:|----------:|------------:|----------:|----------:|----------:|
| gpt-4.1 | 30,000 | 300 | 300 | 300 | 300 | 1,200 (4%) | 28,800 |
| gpt-4.1-mini | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 6,000 (4%) | 144,000 |
| gpt-4.1-nano | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 6,000 (4%) | 144,000 |
| gpt-4o | 30,000 | 300 | 300 | 300 | 300 | 1,200 (4%) | 28,800 |
| gpt-4o-mini | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 6,000 (4%) | 144,000 |
| gpt-5-mini | 10,000 | 100 | 100 | 100 | 100 | 400 (4%) | 9,600 |
| gpt-5-nano | 150,000 | 1,500 | 1,500 | 1,500 | 1,500 | 6,000 (4%) | 144,000 |
| gpt-5.1-chat | 5,000 | 50 | 50 | 50 | 50 | 200 (4%) | 4,800 |
| gpt-5.1-codex-mini | 10,000 | 100 | 100 | 100 | 100 | 400 (4%) | 9,600 |
| o1 | 5,000 | 50 | 50 | 50 | 50 | 200 (4%) | 4,800 |
| o3-mini | 5,000 | 50 | 50 | 50 | 50 | 200 (4%) | 4,800 |
| o4-mini | 10,000 | 100 | 100 | 100 | 100 | 400 (4%) | 9,600 |
| text-embedding-ada-002 | 10,000 | 100 | 100 | 100 | 100 | 400 (4%) | 9,600 |
| text-embedding-3-large | 10,000 | 100 | 100 | 100 | 100 | 400 (4%) | 9,600 |
| text-embedding-3-small | 10,000 | 100 | 100 | 100 | 100 | 400 (4%) | 9,600 |

---

## PROD Environment

Quota allocation strategy: **1% per tenant** for all models. Only wlrs-water-form-assistant is deployed.

| Model | Quota Limit | wlrs (1%) | Total (1%) | Remaining |
|-------|------------:|----------:|----------:|----------:|
| gpt-4.1 | 30,000 | 300 | 300 (1%) | 29,700 |
| gpt-4.1-mini | 150,000 | 1,500 | 1,500 (1%) | 148,500 |
| gpt-4.1-nano | 150,000 | 1,500 | 1,500 (1%) | 148,500 |
| gpt-4o | 30,000 | 300 | 300 (1%) | 29,700 |
| gpt-4o-mini | 150,000 | 1,500 | 1,500 (1%) | 148,500 |
| gpt-5-mini | 10,000 | 100 | 100 (1%) | 9,900 |
| gpt-5-nano | 150,000 | 1,500 | 1,500 (1%) | 148,500 |
| gpt-5.1-chat | 5,000 | 50 | 50 (1%) | 4,950 |
| gpt-5.1-codex-mini | 10,000 | 100 | 100 (1%) | 9,900 |
| o1 | 5,000 | 50 | 50 (1%) | 4,950 |
| o3-mini | 5,000 | 50 | 50 (1%) | 4,950 |
| o4-mini | 10,000 | 100 | 100 (1%) | 9,900 |
| text-embedding-ada-002 | 10,000 | 100 | 100 (1%) | 9,900 |
| text-embedding-3-large | 10,000 | 100 | 100 (1%) | 9,900 |
| text-embedding-3-small | 10,000 | 100 | 100 (1%) | 9,900 |

---

## Content Filters (RAI Policies)

By default every model deployment uses the Azure built-in `Microsoft.DefaultV2` content filter. Tenants can override this per deployment by adding an optional `content_filter` block to `model_deployments` in their `tenant.tfvars`.

### How it works

1. When `content_filter` is present on a deployment, Terraform creates a `Microsoft.CognitiveServices/accounts/raiPolicies` resource on the shared AI Foundry Hub named `<tenant>-<deployment>-filter`.
2. The deployment's `raiPolicyName` is automatically set to that custom policy.
3. Deployments **without** `content_filter` continue to use `Microsoft.DefaultV2` — no change to existing deployments.

### Syntax

```hcl
model_deployments = [
  {
    name          = "gpt-5.1-chat"
    model_name    = "gpt-5.1-chat"
    model_version = "2025-11-13"
    scale_type    = "GlobalStandard"
    capacity      = 50
    content_filter = {
      base_policy_name = "Microsoft.DefaultV2"  # optional, default: Microsoft.DefaultV2
      filters = [
        { name = "hate",     severity_threshold = "High", source = "Prompt",     blocking = true, enabled = true },
        { name = "hate",     severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
        { name = "violence", severity_threshold = "High", source = "Prompt",     blocking = true, enabled = true },
        { name = "violence", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
        { name = "sexual",   severity_threshold = "High", source = "Prompt",     blocking = true, enabled = true },
        { name = "sexual",   severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
        { name = "selfharm", severity_threshold = "High", source = "Prompt",     blocking = true, enabled = true },
        { name = "selfharm", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
      ]
    }
  },
]
```

### Filter field reference

| Field | Allowed values | Required | Description |
|-------|---------------|----------|-------------|
| `name` | `hate` `violence` `sexual` `selfharm` | Yes | Content category to configure |
| `severity_threshold` | `Low` `Medium` `High` | Yes | Severity level at which the filter activates |
| `source` | `Prompt` `Completion` | Yes | Apply to user input (`Prompt`) or model output (`Completion`) |
| `blocking` | `true` `false` | No | Hard-block the request (default: `true`) |
| `enabled` | `true` `false` | No | Toggle the filter entry on/off (default: `true`) |

> **Tip:** Each category + source combination is a separate filter entry. Define one entry per `name` × `source` pair you want to customise. Omitted pairs inherit the behaviour from `base_policy_name`.

---

## How to Update This Document

When adding a new tenant or modifying model deployments:

1. Update the tenant's `tenant.tfvars` file under `params/<env>/tenants/<tenant>/`
2. Run `deploy-terraform.sh apply <env>` to apply changes
3. **Update the corresponding environment table above** with the new capacity values and percentages
4. Verify totals don't exceed regional quota limits

### Calculating Capacity from Percentage

```
capacity = floor(quota_limit × percentage / 100)
```

Example: 1% of gpt-5-mini (10,000 limit) = `floor(10000 × 0.01)` = **100**

### Checking Current Quota Usage

```bash
az cognitiveservices usage list \
  --location "canadaeast" \
  --subscription "<subscription-id>" \
  -o table
```
