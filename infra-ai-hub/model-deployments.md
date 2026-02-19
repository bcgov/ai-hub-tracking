# Model Deployments & Quota Allocation

> **IMPORTANT:** This file must be updated whenever tenants are added, removed, or their model deployments are modified.
> See [IaC Coder Skills](../.github/skills/iac-coder/SKILLS.md) for the mandatory update rule.

This document tracks the OpenAI model capacity allocated to each tenant across all environments.
Capacity values are in **thousands of Tokens Per Minute (TPM)** — the Azure OpenAI deployment unit.
Percentage values show the share of the regional quota limit consumed by each tenant.

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

---

## TEST Environment

Quota allocation strategy: **1% per tenant** for all models.

| Model | Quota Limit | wlrs (1%) | sdpr (1%) | nr-dap (1%) | Total (3%) | Remaining |
|-------|------------:|----------:|----------:|------------:|----------:|----------:|
| gpt-4.1 | 30,000 | 300 | 300 | 300 | 900 (3%) | 29,100 |
| gpt-4.1-mini | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-4.1-nano | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-4o | 30,000 | 300 | 300 | 300 | 900 (3%) | 29,100 |
| gpt-4o-mini | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-5-mini | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| gpt-5-nano | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-5.1-chat | 5,000 | 50 | 50 | 50 | 150 (3%) | 4,850 |
| gpt-5.1-codex-mini | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| o1 | 5,000 | 50 | 50 | 50 | 150 (3%) | 4,850 |
| o3-mini | 5,000 | 50 | 50 | 50 | 150 (3%) | 4,850 |
| o4-mini | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| text-embedding-ada-002 | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| text-embedding-3-large | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| text-embedding-3-small | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |

---

## DEV Environment

Quota allocation strategy: **1% per tenant** for all models.

| Model | Quota Limit | wlrs (1%) | sdpr (1%) | nr-dap (1%) | Total (3%) | Remaining |
|-------|------------:|----------:|----------:|------------:|----------:|----------:|
| gpt-4.1 | 30,000 | 300 | 300 | 300 | 900 (3%) | 29,100 |
| gpt-4.1-mini | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-4.1-nano | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-4o | 30,000 | 300 | 300 | 300 | 900 (3%) | 29,100 |
| gpt-4o-mini | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-5-mini | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| gpt-5-nano | 150,000 | 1,500 | 1,500 | 1,500 | 4,500 (3%) | 145,500 |
| gpt-5.1-chat | 5,000 | 50 | 50 | 50 | 150 (3%) | 4,850 |
| gpt-5.1-codex-mini | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| o1 | 5,000 | 50 | 50 | 50 | 150 (3%) | 4,850 |
| o3-mini | 5,000 | 50 | 50 | 50 | 150 (3%) | 4,850 |
| o4-mini | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| text-embedding-ada-002 | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| text-embedding-3-large | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |
| text-embedding-3-small | 10,000 | 100 | 100 | 100 | 300 (3%) | 9,700 |

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
