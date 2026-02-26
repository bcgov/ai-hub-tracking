# Documentation — Detailed Reference

Supplementary reference for the [Documentation skill](../SKILL.md). Load this file when you need change trigger mappings, file conventions, or failure playbooks.

## Required Updates

- If infrastructure or networking behavior changes, update docs pages accordingly.
- Keep docs/README.md aligned with current documentation workflow.

## Change Trigger Map

Use this map to avoid missed docs updates:

| Change Type | Minimum Docs Impact |
|---|---|
| Terraform module behavior change | Update relevant docs page(s) and references in `docs/terraform*.html` if applicable |
| APIM routing/policy behavior change | Update APIM/runbook pages and FAQ entries that describe route/auth behavior |
| Deployment workflow/script changes | Update setup/runbook pages and any command examples |
| Operational workaround or lifecycle pattern change | Document rationale, scope, and rollback/verification notes |

## File Conventions

- Use existing HTML structure and indentation.
- Prefer editing docs/_pages/*.html and regenerate docs/*.html when appropriate.
- Keep _partials clean and reusable.

## Failure Playbook

### Drift between source and published pages
- Reconcile `docs/_pages/*` against generated `docs/*.html` and regenerate as needed.

### Conflicting instructions across pages
- Move shared guidance into `docs/_partials/` and reference it from pages.

### Infra behavior changed but docs stale
- Update docs in the same change window as infra updates; treat stale docs as incomplete delivery.
