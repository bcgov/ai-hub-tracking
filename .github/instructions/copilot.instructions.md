# Copilot Preferences for ai-hub-tracking

## Task Completion

After completing tasks:
- ✅ DO: Provide brief confirmation in chat (1-2 sentences)
- ❌ DON'T: Create summary markdown files

## Brief Status Format

Use this format for task completion:
✅ [Task Name] Complete

Change 1
Change 2
Verified: [confirmation]

---

## Skills-Based Work

This repo uses **skill profiles** to guide work. Use the appropriate skill profile based on the task:

### [IaC Coder](../skills/iac-coder/SKILLS.md)
Use when creating or modifying infrastructure code (Terraform, Bash, GitHub Actions).
- Terraform (>= 1.12.0) with Azure providers
- Azure Verified Modules (AVM)
- GitHub Actions workflows with OIDC
- Bash scripts for Terraform operations

### [Documentation](../skills/documentation/SKILLS.md)
Use when creating or updating documentation under docs/.
- Static HTML pages and templates
- Shared partials and content
- Update procedures and content standards

### [API Management](../skills/api-management/SKILLS.md)
Use when creating or modifying APIM policies and routing.
- Policy files under `infra-ai-hub/params/apim/`
- Routing rules and authentication
- Rate limiting and error handling

### [Integration Testing](../skills/integration-testing/SKILLS.md)
Use when creating, modifying, or debugging integration tests.
- bats-core test suites under `tests/integration/`
- Test helpers, config loading, and assertion patterns
- Retry logic, skip guards, and async polling

### [External Docs Research](../skills/external-docs/SKILLS.md)
Use when researching authoritative external docs for platform behavior and versioned guidance.
- Repository-first validation, then Learn/Context7 lookup
- Upstash Context7 for non-Learn sources and targeted version/topic queries
- Explicit fallback approval required when Context7 has no documentation