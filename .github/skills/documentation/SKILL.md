---
name: documentation
description: Guidance for maintaining documentation in the docs/ site for ai-hub-tracking. Use when updating HTML pages, partials, build scripts, or Terraform reference docs.
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

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Documentation Sync
- If the change adds, removes, renames, or materially reorganizes tracked files or directories, update the root `README.md` `Folder Structure` section in the same change. Do not add gitignored or local-only artifacts to that tree.
- Review the documentation sync matrix in [../../copilot-instructions.md](../../copilot-instructions.md) and update any area-specific README or docs pages it calls out for the touched subtree.

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

## Detailed References

For change trigger maps, file conventions, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
