# Copilot Guidance Update Summary

Branch: `chore/update-copilot-instructions-and-skills`

## Methodology

Audited all 11 skill profiles in `.github/skills/*/SKILL.md` and the master routing document `.github/copilot-instructions.md` for structural consistency, completeness, and alignment with the actual codebase (stacks, modules, workflows, tests).

---

## Changes Made

### 1. `.github/copilot-instructions.md` — Added PII Redaction Service subsection

**What changed:** Added a new `### [PII Redaction Service]` subsection to the Skills-Based Work section, placed before the IaC Code Reviewer entry.

**Source citation:** All 10 other skills listed in Skills-Based Work have descriptive subsections with "Use when..." trigger lines and bullet-pointed scope summaries. PII Redaction Service was the **only** skill with a Skills-Based Work reference but no subsection — despite having a complete SKILL.md file at `.github/skills/pii-redaction-service/SKILL.md`.

**Advantage:** Copilot can now route PII redaction tasks (FastAPI code, batch orchestration, Language Service integration, Container App scaling, Terraform stack) to the correct skill profile without the user having to specify it explicitly. Previously, the missing subsection meant Copilot had no trigger text to match against for PII redaction work.

---

### 2. `.github/skills/tenant-onboarding-portal/SKILL.md` — Structural alignment

**What changed:**
- Added **Use When** section (6 trigger conditions derived from existing scope and domain content)
- Added **Do Not Use When** section (4 cross-references to IaC Coder, API Management, Documentation, IaC Code Reviewer)
- Added **Input Contract** section (4 required context items)
- Added **Output Contract** section (4 deliverables)
- Added **External Documentation** reference (points to External Docs Research skill)
- Renamed **Post-Implementation Hook** → **Validation Gates (Required)** (content unchanged)
- Renamed **Implementation Rules** → **Change Checklist** (content unchanged)

**Source citation:** All other 10 skill profiles follow a consistent structural template:
```
Use When → Do Not Use When → Input Contract → Output Contract → External Documentation → Scope → [domain sections] → Change Checklist → Validation Gates → Detailed References
```
The tenant-onboarding-portal skill was the **only** skill that omitted these standard sections, using non-standard heading names (`Post-Implementation Hook` instead of `Validation Gates`, `Implementation Rules` instead of `Change Checklist`) and lacking cross-references to other skills.

**Advantage:**
- **Routing accuracy:** Copilot can now use the structured `Use When` / `Do Not Use When` sections to correctly route portal tasks to this skill and avoid loading it for unrelated IaC or APIM work.
- **Consistency:** All 11 skill profiles now share the same structural template, making it easier for contributors to understand expectations and for Copilot to parse skill boundaries.
- **Cross-skill awareness:** The `Do Not Use When` cross-references prevent Copilot from using the wrong skill when working near the portal (e.g., modifying portal Terraform should load IaC Coder instead).

---

### 3. `.github/skills/integration-testing/SKILL.md` — Added 3 missing test suites

**What changed:** Added 3 entries to the Test Suites table:

| File | Focus |
|---|---|
| `tenant-info.bats` | Tenant info endpoint, model deployments, and feature flags |
| `pii-failure.bats` | PII redaction failure scenarios, fail-closed 503 behavior |
| `mistral.bats` | Mistral chat and OCR routing via APIM |

**Source citation:** The Test Suites table listed 11 `.bats` files, but `file_search` for `tests/integration/*.bats` returned **14 files**. The 3 unlisted files were verified by reading their headers:
- `tenant-info.bats` — tests `/internal/tenant-info` APIM endpoint for tenant model deployments and feature flags
- `pii-failure.bats` — tests PII redaction fail-closed behavior (503 responses when Language Service is unreachable); referenced in `pii-redaction-service/SKILL.md` validation gate #9 but absent from the integration-testing skill
- `mistral.bats` — tests Mistral-specific chat and OCR document routing for the `ai-hub-admin` tenant

**Advantage:** When Copilot is asked to write or debug integration tests for tenant-info endpoints, PII failure scenarios, or Mistral routing, it now knows these test suites exist. Previously, Copilot might create duplicate test files or miss existing test patterns because the skill didn't acknowledge their existence.

---

## Files Not Changed

The following 8 skill profiles were audited and found to be structurally complete, consistent, and aligned with the codebase:

| Skill | Reason no change needed |
|---|---|
| `iac-coder` | Full template structure, accurate stack/module references |
| `documentation` | Full template structure, accurate folder map |
| `api-management` | Full template structure, 10 routing rules match actual policies |
| `app-gateway` | Full template structure, WAF priority map and rewrite sequence map accurate |
| `key-rotation-function` | Full template structure, code locations and env vars match actual code |
| `network` | Full template structure, subnet allocation model and PE pool math accurate |
| `external-docs` | Full template structure, Context7 workflow documented |
| `iac-code-reviewer` | Full template structure, review checklist with severity assignments |
