---
name: External Docs Research
description: Guidance for researching authoritative external documentation using Microsoft Learn MCP and Upstash Context7, with explicit approval for fallback sources.
---

# External Docs Research Skills

Use this skill profile when you need authoritative external documentation before implementing or reviewing changes.

## Use When
- Looking up external platform behavior, limits, syntax, API contracts, or version-specific guidance
- Verifying configuration for Azure, GitHub, VS Code, Terraform ecosystem tools, SDKs, or service APIs
- Resolving uncertainty where repository-local code is not a complete source of truth

## Do Not Use When
- The answer is fully determined by repository-local code and docs
- Runtime/test evidence in this repo already proves behavior conclusively
- You are making speculative changes without a concrete external dependency

## Input Contract
Required before research:
- Technology/service name and version (if applicable)
- Task intent (`quickstart`, `reference`, `limits`, `migration`, `how-to`)
- Language/runtime context (`bash`, `yaml`, `terraform`, `python`, `csharp`, etc.)

## Output Contract
Research output should include:
- Source used (Learn/Context7/approved fallback)
- Version/topic scope queried
- Repo-specific recommendation (what to change and where)
- Explicit assumptions or uncertainty notes

## Source-of-Truth Policy (Single Authority)
1. **Repository first**: validate local patterns and current implementation.
2. **Microsoft Learn MCP next**: use for content on `learn.microsoft.com` when available.
3. **Upstash Context7 for external docs**: resolve library ID first, then query exact topic/version.
4. **Conflict handling**: prefer official versioned docs over memory or unofficial sources.
5. **Fallback approval requirement**: if no documentation is found in Context7, identify an alternate source of truth and ask the user for explicit approval before using it, or ask the user to provide the alternate source directly.

## Context7 Workflow
1. Resolve library ID with `mcp_context7_resolve-library-id`.
2. Query docs with `mcp_context7_get-library-docs` using a specific, version-aware topic.
3. Capture key constraints and map them to repository changes.

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

## Validation Gates (Required)
1. Confirm source authority and version relevance.
2. Confirm recommendation aligns with repository constraints and patterns.
3. Flag conflicts between docs and repository behavior.
4. State what could not be verified and why.

## Failure Playbook
### Conflicting external guidance
- Prefer newest official versioned source and note discrepancy.

### No direct docs for edge behavior
- Use closest official source plus repository precedent; label assumptions.

### No Context7 coverage
- Request explicit user approval for a fallback source or request user-provided source.
