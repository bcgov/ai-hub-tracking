
---
name: Documentation
description: Guidance for maintaining documentation in the docs/ site for ai-hub-tracking.
---

# Documentation Skills

Use this skill profile when creating or updating documentation under docs/.

## Use When
- Updating technical docs for infrastructure, operations, or architecture changes
- Editing shared page templates/partials used by multiple docs pages
- Regenerating published pages from source templates after content updates

## Do Not Use When
- Implementing infrastructure or policy changes without documentation work
- Performing code-review-only tasks with no docs modifications
- Editing non-doc assets/code that does not affect documentation outputs

## Input Contract
Required context before doc edits:
- What changed in code/infra and why operators/readers need the update
- Target audience (engineers, operators, platform team, security reviewers)
- Source of truth files/sections that docs should reference

## Output Contract
Every docs update should provide:
- Source updates in `docs/_pages/` or `docs/_partials/` as appropriate
- Regenerated/updated published page(s) under `docs/*.html` when required
- Link/anchor integrity for any added or moved sections
- Clear, concise wording aligned with existing docs tone and structure

## Scope
- Static HTML pages in docs/
- Source templates in docs/_pages/
- Shared partials in docs/_partials/
- Static assets in docs/assets/
- Site build scripts in docs/build.sh and docs/generate-tf-docs.sh

## Folder Map
- docs/*.html: Published pages
- docs/_pages/*.html: Source page templates
- docs/_partials/: Shared header/footer
- docs/assets/: Images, styles, and static assets

## Update Workflow
1. Edit source templates in docs/_pages/ where possible.
2. Update shared content in docs/_partials/ for site-wide changes.
3. Run `docs/build.sh` to regenerate published docs/*.html from _pages + _partials.
4. When Terraform modules, variables, or outputs change, run `docs/generate-tf-docs.sh` to regenerate `docs/_pages/terraform-reference.html`, then re-run `docs/build.sh` to publish it.

## Content Standards
- Keep headings consistent with existing pages.
- Avoid duplicating content across pages; use partials for shared sections.
- Ensure links are relative and stable within the docs/ structure.
- For infra or networking changes, update relevant pages in docs/.

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

## Quick Checklist
- [ ] Updated the correct source page in docs/_pages/
- [ ] Shared content updated in docs/_partials/ if needed
- [ ] Related published docs/*.html updated or regenerated
- [ ] Links and anchors validated

## Validation Gates (Required)
1. Structural check: heading hierarchy and page layout remain consistent.
2. Link check: changed links/anchors resolve correctly within `docs/`.
3. Scope check: docs reflect actual behavior, not planned/unimplemented behavior.
4. Consistency check: terminology and command examples match current repo usage.

## Failure Playbook
### Drift between source and published pages
- Reconcile `docs/_pages/*` against generated `docs/*.html` and regenerate as needed.

### Conflicting instructions across pages
- Move shared guidance into `docs/_partials/` and reference it from pages.

### Infra behavior changed but docs stale
- Update docs in the same change window as infra updates; treat stale docs as incomplete delivery.
