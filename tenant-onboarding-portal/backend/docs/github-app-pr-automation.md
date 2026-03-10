# GitHub App PR Automation Guide

This document describes a future enhancement for automated PR creation from the Tenant Onboarding Portal. The feature is still not implemented.

## Architecture

When an admin approves a tenant request in the portal, the backend would:

1. Generate `tenant.tfvars` files for all three environments.
2. Create a feature branch in this repository.
3. Commit the tfvars files to the correct paths.
4. Open a PR targeting `main` with appropriate labels and description.

## Setup Outline

1. Create a GitHub App in the BCGov organization with `Contents`, `Pull requests`, and `Metadata` permissions.
2. Install the app on `bcgov/ai-hub-tracking`.
3. Store the app credentials or installation token source in Azure Key Vault.

## NestJS Integration Sketch

Add GitHub API dependencies to the portal backend:

```json
{
  "dependencies": {
    "@octokit/rest": "^22.0.0"
  }
}
```

Example service outline:

```ts
import { DefaultAzureCredential } from '@azure/identity'
import { SecretClient } from '@azure/keyvault-secrets'
import { Octokit } from '@octokit/rest'

export class GitHubPrService {
  constructor(private readonly keyVaultUrl: string) {}

  async createTenantPr(tenantName: string, version: string, tfvars: Record<string, string>, submittedBy: string) {
    const credential = new DefaultAzureCredential()
    const secrets = new SecretClient(this.keyVaultUrl, credential)
    const installationToken = (await secrets.getSecret('github-app-installation-token')).value
    if (!installationToken) {
      throw new Error('Missing GitHub App installation token')
    }

    const octokit = new Octokit({ auth: installationToken })
    return octokit
  }
}
```

Example approval wiring in the Nest controller/service layer:

```ts
@Post('api/admin/approve/:tenantName/:version')
async approveRequest(...) {
  await this.tenantStore.updateStatus(tenantName, version, 'approved', user.email, reviewNotes)

  const tenantData = await this.tenantStore.getVersion(tenantName, version)
  if (tenantData?.GeneratedTfvars) {
    await this.gitHubPrService.createTenantPr(
      tenantName,
      version,
      tenantData.GeneratedTfvars,
      tenantData.SubmittedBy,
    )
  }
}
```

## Key Considerations

- Keep approval state changes independent from PR creation so retries are safe.
- Use short-lived GitHub App credentials or installation tokens.
- Preserve auditability in commit messages and PR bodies.
- Add explicit error handling and retry behavior before implementing this in production.
