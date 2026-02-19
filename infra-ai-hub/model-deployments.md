# Model Deployments & Quota Allocation

> **IMPORTANT:** This file must be updated whenever tenants are added, removed, or their model deployments are modified.
> See [IaC Coder Skills](../.github/skills/iac-coder/SKILLS.md) for the mandatory update rule.

This document tracks the OpenAI model capacity allocated to each tenant across all environments.
Capacity values are in **thousands of Tokens Per Minute (TPM)** — the Azure OpenAI deployment unit.
Percentage values show the share of the regional quota limit consumed by each tenant.

## Regional Quota Limits (Canada East)

These are the maximum TPM quotas available per model across the entire subscription.

| Model | Quota Limit (TPM) |
|-------|------------------:|
| gpt-4.1-mini | 150,000 |
| gpt-5-mini | 10,000 |
| gpt-5-nano | 150,000 |
| gpt-5.1-chat | 5,000 |
| gpt-5.1-codex-mini | 10,000 |
| text-embedding-ada-002 | 10,000 |
| text-embedding-3-large | 10,000 |

---

## TEST Environment

Quota allocation strategy: **wlrs = 3%, sdpr = 2%, nr-dap = 1%** of regional limit per model.

| Model | Quota Limit | wlrs-water-form-assistant | sdpr-invoice-automation | nr-dap-fish-wildlife | Total Allocated | Remaining |
|-------|------------:|--------------------------:|------------------------:|---------------------:|----------------:|----------:|
| gpt-4.1-mini | 150,000 | 4,500 (3%) | 3,000 (2%) | — | 7,500 (5%) | 142,500 |
| gpt-5-mini | 10,000 | 300 (3%) | 200 (2%) | 100 (1%) | 600 (6%) | 9,400 |
| gpt-5-nano | 150,000 | 4,500 (3%) | 3,000 (2%) | 1,500 (1%) | 9,000 (6%) | 141,000 |
| gpt-5.1-chat | 5,000 | 150 (3%) | 100 (2%) | 50 (1%) | 300 (6%) | 4,700 |
| gpt-5.1-codex-mini | 10,000 | 300 (3%) | 200 (2%) | 100 (1%) | 600 (6%) | 9,400 |
| text-embedding-ada-002 | 10,000 | 300 (3%) | 200 (2%) | 100 (1%) | 600 (6%) | 9,400 |
| text-embedding-3-large | 10,000 | 300 (3%) | — | — | 300 (3%) | 9,700 |

> **Note:** `text-embedding-3-large` is not deployed for nr-dap-fish-wildlife or sdpr-invoice-automation — add when quota is freed up.

---

## DEV Environment

Dev capacities are higher than test for active development. No percentage-based allocation is enforced yet.

| Model | Quota Limit | wlrs-water-form-assistant | sdpr-invoice-automation | nr-dap-fish-wildlife | Total Allocated | Remaining |
|-------|------------:|--------------------------:|------------------------:|---------------------:|----------------:|----------:|
| gpt-4.1-mini | 150,000 | 30,000 | 7,500 | — | 37,500 | 112,500 |
| gpt-5-mini | 10,000 | 2,000 | 500 | 200 | 2,700 | 7,300 |
| gpt-5-nano | 150,000 | 30,000 | 7,500 | 300 | 37,800 | 112,200 |
| gpt-5.1-chat | 5,000 | 1,000 | 250 | 50 | 1,300 | 3,700 |
| gpt-5.1-codex-mini | 10,000 | 2,000 | 500 | 20 | 2,520 | 7,480 |
| text-embedding-ada-002 | 10,000 | 2,000 | 500 | 50 | 2,550 | 7,450 |
| text-embedding-3-large | 10,000 | 10,000 | — | — | 10,000 | 0 |

> **Note:** `text-embedding-3-large` quota is fully consumed by wlrs in dev (10,000/10,000). Other tenants cannot deploy this model until quota is increased or freed up.

---

## PROD Environment

Prod currently has minimal placeholder capacities (10 TPM each). Only wlrs-water-form-assistant is deployed.

| Model | Quota Limit | wlrs-water-form-assistant | Total Allocated | Remaining |
|-------|------------:|--------------------------:|----------------:|----------:|
| gpt-4.1-mini | 150,000 | 10 | 10 | 149,990 |
| gpt-5-mini | 10,000 | 10 | 10 | 9,990 |
| gpt-5-nano | 150,000 | 10 | 10 | 149,990 |
| gpt-5.1-chat | 5,000 | 10 | 10 | 4,990 |
| gpt-5.1-codex-mini | 10,000 | 10 | 10 | 9,990 |
| text-embedding-ada-002 | 10,000 | 10 | 10 | 9,990 |

> **Note:** Prod capacities are placeholder values. Adjust before production traffic begins.

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

Example: 3% of gpt-5-mini (10,000 limit) = `floor(10000 × 0.03)` = **300**

### Checking Current Quota Usage

```bash
az cognitiveservices usage list \
  --location "canadaeast" \
  --subscription "<subscription-id>" \
  -o table
```
