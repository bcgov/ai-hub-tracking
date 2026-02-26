# External Docs Research — Detailed Reference

Supplementary reference for the [External Docs Research skill](../SKILL.md). Load this file when you need Context7 target details, query construction guidance, or failure playbooks.

## Common Context7 Targets

| Library ID | Use for |
|---|---|
| `/websites/github_en` | GitHub Actions, repos, security, Copilot, API docs |
| `/websites/cli_github` | `gh` CLI command and flag behavior |
| `/websites/code_visualstudio` | VS Code user docs/settings/workflows |
| `/websites/code_visualstudio_api` | VS Code extension API/contribution points |

## Query Quality Rules

- Include version where relevant (`.NET 8`, `Terraform 1.12`, `VS Code 1.96`).
- Include intent (`reference`, `limits`, `how-to`, `migration`).
- Include domain context (`APIM policy`, `OIDC`, `rate limiting`, `private endpoints`).
- Prefer narrow, testable queries over broad terms.

## Failure Playbook

### Conflicting external guidance
- Prefer newest official versioned source and note discrepancy.

### No direct docs for edge behavior
- Use closest official source plus repository precedent; label assumptions.

### No Context7 coverage
- Request explicit user approval for a fallback source or request user-provided source.
