# GitHub App PR Automation Guide

This document describes how to set up automated PR creation from the Tenant Onboarding Portal using a GitHub App. **This feature is not yet implemented** — it is documented here for future implementation.

## Architecture

When an admin approves a tenant request in the portal, the backend should:

1. Generate `tenant.tfvars` files for all three environments (dev/test/prod)
2. Create a feature branch in this repository
3. Commit the tfvars files to the correct paths
4. Open a PR targeting `main` with appropriate labels and description

## Setting Up the GitHub App

### 1. Create the GitHub App

1. Go to **BCGov org settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
2. Configure:
   - **Name**: `AI Hub Tenant Portal`
   - **Homepage URL**: Portal URL
   - **Webhook**: Disable (not needed — we push, not listen)
   - **Permissions**:
     - Repository: `Contents: Read & Write` (to create branches and commit files)
     - Repository: `Pull requests: Read & Write` (to create PRs)
     - Repository: `Metadata: Read` (required)
   - **Where can this app be installed?**: Only on this account

3. After creation, note the **App ID**
4. Generate a **Private Key** (`.pem` file) — download and store securely

### 2. Install the App on This Repository

1. Go to the App's settings → **Install App**
2. Select the `bcgov` organization
3. Choose **Only select repositories** → select `ai-hub-tracking`
4. Note the **Installation ID** from the URL after install

### 3. Store Secrets in Azure Key Vault

Store these in the portal's Key Vault (accessed via Managed Identity):

| Secret Name                    | Value                              |
| ------------------------------ | ---------------------------------- |
| `github-app-id`               | The App ID from step 1             |
| `github-app-private-key`      | Contents of the `.pem` file        |
| `github-app-installation-id`  | Installation ID from step 2        |

### 4. FastAPI Integration

#### Install PyGithub

Add to `pyproject.toml`:
```toml
"PyGithub>=2.5,<3",
```

#### Implementation Pattern

```python
"""GitHub App PR creation service."""

from __future__ import annotations

import base64
from typing import Any

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from github import Auth, Github, GithubIntegration


class GitHubPRService:
    """Creates PRs via a GitHub App installed on the repository."""

    REPO = "bcgov/ai-hub-tracking"
    BASE_BRANCH = "main"

    def __init__(self, key_vault_url: str):
        credential = DefaultAzureCredential()
        kv_client = SecretClient(vault_url=key_vault_url, credential=credential)

        self._app_id = int(kv_client.get_secret("github-app-id").value)
        self._private_key = kv_client.get_secret("github-app-private-key").value
        self._installation_id = int(kv_client.get_secret("github-app-installation-id").value)

    def _get_github_client(self) -> Github:
        """Get an authenticated GitHub client with a short-lived installation token."""
        auth = Auth.AppAuth(self._app_id, self._private_key)
        gi = GithubIntegration(auth=auth)
        installation_auth = gi.get_access_token(self._installation_id)
        return Github(auth=Auth.Token(installation_auth.token))

    def create_tenant_pr(
        self,
        tenant_name: str,
        version: str,
        tfvars: dict[str, str],
        submitted_by: str,
    ) -> str:
        """Create a PR with generated tenant.tfvars for all environments.

        Args:
            tenant_name: The tenant slug (e.g., "my-project")
            version: The version string (e.g., "v3")
            tfvars: Dict mapping environment -> tfvars content
            submitted_by: Email of the requester

        Returns:
            The PR URL
        """
        gh = self._get_github_client()
        repo = gh.get_repo(self.REPO)

        # 1. Create branch from main
        main_ref = repo.get_git_ref("heads/main")
        branch_name = f"tenant/{tenant_name}-{version}"
        repo.create_git_ref(
            ref=f"refs/heads/{branch_name}",
            sha=main_ref.object.sha,
        )

        # 2. Commit tfvars files for each environment
        for env, content in tfvars.items():
            file_path = f"infra-ai-hub/params/{env}/tenants/{tenant_name}/tenant.tfvars"
            try:
                # Update existing file
                existing = repo.get_contents(file_path, ref=branch_name)
                repo.update_file(
                    path=file_path,
                    message=f"feat(tenant): update {tenant_name} {env} config ({version})",
                    content=content,
                    sha=existing.sha,
                    branch=branch_name,
                )
            except Exception:
                # Create new file
                repo.create_file(
                    path=file_path,
                    message=f"feat(tenant): add {tenant_name} {env} config ({version})",
                    content=content,
                    branch=branch_name,
                )

        # 3. Create PR
        pr = repo.create_pull(
            title=f"feat(tenant): onboard {tenant_name} ({version})",
            body=self._pr_body(tenant_name, version, submitted_by),
            head=branch_name,
            base=self.BASE_BRANCH,
        )

        # 4. Add labels
        pr.add_to_labels("tenant-onboarding", "auto-generated")

        return pr.html_url

    @staticmethod
    def _pr_body(tenant_name: str, version: str, submitted_by: str) -> str:
        return f"""## Tenant Onboarding: {tenant_name}

**Version**: {version}
**Requested by**: {submitted_by}
**Generated by**: Tenant Onboarding Portal

### Changes
- Adds/updates `tenant.tfvars` for dev, test, and prod environments

### Review Checklist
- [ ] Verify tenant configuration looks correct
- [ ] Check PE subnet assignment
- [ ] Confirm model deployment capacities
- [ ] Review APIM policy settings
"""
```

#### Wiring into the Approval Flow

In `src/routers/admin.py`, after approval:

```python
@router.post("/approve/{tenant_name}/{version}")
async def approve_request(...):
    store = TenantStore()
    store.update_status(tenant_name, version, "approved", ...)

    # Create PR automatically
    tenant_data = store.get_version(tenant_name, version)
    if tenant_data and tenant_data.get("GeneratedTfvars"):
        pr_service = GitHubPRService(key_vault_url=settings.key_vault_url)
        pr_url = pr_service.create_tenant_pr(
            tenant_name=tenant_name,
            version=version,
            tfvars=tenant_data["GeneratedTfvars"],
            submitted_by=tenant_data["SubmittedBy"],
        )
        # Store PR URL in the request record
        store.update_pr_url(tenant_name, version, pr_url)
```

## Key Considerations

- **Token lifetime**: GitHub App installation tokens expire after 1 hour. Always generate a fresh token per operation.
- **Rate limits**: GitHub App tokens have 5,000 requests/hour — more than sufficient.
- **Audit trail**: All commits show the GitHub App as the author, with the tenant name and version in the commit message.
- **Error handling**: If PR creation fails, the approval status should still be saved. Add a retry mechanism or a manual "Create PR" button.
- **Branch protection**: Ensure the App is allowed to push to protected branches (add it to the bypass list if needed).
