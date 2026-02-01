
---
name: Documentation
description: Guidance for maintaining documentation in the docs/ site for ai-hub-tracking.
---

# Documentation Skills

Use this skill profile when creating or updating documentation under docs/.

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
3. Regenerate or rebuild docs pages if required by scripts.

## Content Standards
- Keep headings consistent with existing pages.
- Avoid duplicating content across pages; use partials for shared sections.
- Ensure links are relative and stable within the docs/ structure.
- For infra or networking changes, update relevant pages in docs/.

## Required Updates
- If infrastructure or networking behavior changes, update docs pages accordingly.
- Keep docs/README.md aligned with current documentation workflow.

## File Conventions
- Use existing HTML structure and indentation.
- Prefer editing docs/_pages/*.html and regenerate docs/*.html when appropriate.
- Keep _partials clean and reusable.

## Quick Checklist
- [ ] Updated the correct source page in docs/_pages/
- [ ] Shared content updated in docs/_partials/ if needed
- [ ] Related published docs/*.html updated or regenerated
- [ ] Links and anchors validated
