import { Injectable, Logger } from '@nestjs/common';

import { getSettings } from '../config/settings';

/**
 * A single file to commit into the tenant onboarding pull request.
 */
export interface TenantPrFile {
  path: string;
  content: string;
}

/**
 * Metadata describing the approved tenant request, used to build the
 * feature branch name, commit message, and pull request body.
 */
export interface TenantPrMeta {
  projectName: string;
  displayName: string;
  ministry: string;
  department?: string;
  submittedBy: string;
  approvedBy: string;
  reviewNotes?: string;
  services?: Record<string, boolean>;
  modelFamilies?: string[];
  capacityTier?: string;
  version: string;
}

/**
 * Result of a successful pull request creation (or reuse of an open one).
 */
export interface TenantPrResult {
  branch: string;
  prUrl: string;
  prNumber: number;
}

const PR_LABELS = [
  {
    name: 'tenant-onboarding',
    color: '013366',
    description: 'AI Services Hub tenant onboarding request',
  },
  { name: 'automated', color: 'fcba19', description: 'Opened by portal automation' },
];

/**
 * Opens tenant onboarding pull requests in the infrastructure repository when
 * an admin approves a request in the portal.
 *
 * Talks to the GitHub REST API with the native `fetch` client, so it needs
 * neither `git` nor the `gh` CLI on the host. On approval it creates a feature
 * branch, commits the generated `tenant.tfvars` files under
 * `infra-ai-hub/params/<env>/tenants/<tenant>/tenant.tfvars` in a single
 * commit, and opens a pull request against the base branch. The PR is then
 * reviewed, planned, and merged through the normal GitHub workflow.
 *
 * Creation is idempotent per tenant version: the branch is force-updated and an
 * already-open PR for the same branch is reused, so a failed approval can be
 * retried safely.
 */
@Injectable()
export class GitHubOpsService {
  private readonly logger = new Logger(GitHubOpsService.name);

  /**
   * Returns whether GitHub integration is configured (token + repo present).
   *
   * @returns `true` when a token and target repository are configured.
   */
  isEnabled(): boolean {
    const settings = getSettings();
    return Boolean(settings.githubToken && settings.githubRepo);
  }

  /**
   * Builds the deterministic feature-branch name for a tenant version.
   *
   * @param meta - The tenant request metadata.
   * @returns The branch name, e.g. `tenant/my-project-v1`.
   */
  branchName(meta: Pick<TenantPrMeta, 'projectName' | 'version'>): string {
    return `tenant/${meta.projectName}-${meta.version.toLowerCase()}`;
  }

  /**
   * Creates (or force-updates) the feature branch, commits the tfvars files in a
   * single commit, and opens a pull request against the base branch. When an
   * open PR already exists for the branch it is reused instead.
   *
   * @param meta - Tenant request metadata used for naming and the PR body.
   * @param files - The tfvars files to commit (path relative to repo root).
   * @returns The PR's branch, URL, and number.
   * @throws Error when any required GitHub API call fails.
   */
  async createTenantPR(meta: TenantPrMeta, files: TenantPrFile[]): Promise<TenantPrResult> {
    const settings = getSettings();
    const base = settings.githubBaseBranch;
    const branch = this.branchName(meta);

    const baseSha = await this.getBranchSha(base);
    const baseCommit = await this.api<{ tree: { sha: string } }>('GET', `/git/commits/${baseSha}`);

    const treeItems = [];
    for (const file of files) {
      const blob = await this.api<{ sha: string }>('POST', '/git/blobs', {
        content: Buffer.from(file.content, 'utf-8').toString('base64'),
        encoding: 'base64',
      });
      treeItems.push({ path: file.path, mode: '100644', type: 'blob', sha: blob.sha });
    }

    const tree = await this.api<{ sha: string }>('POST', '/git/trees', {
      base_tree: baseCommit.tree.sha,
      tree: treeItems,
    });

    const title = `Onboard tenant: ${meta.displayName} (${meta.projectName}) ${meta.version}`;
    const body = this.buildPrBody(meta, files);
    const commit = await this.api<{ sha: string }>('POST', '/git/commits', {
      message: `${title}\n\nSubmitted-by: ${meta.submittedBy}\nApproved-by: ${meta.approvedBy}`,
      tree: tree.sha,
      parents: [baseSha],
    });

    await this.upsertBranchRef(branch, commit.sha);

    const existing = await this.findOpenPr(branch);
    if (existing) {
      this.logger.log(`Reusing open PR #${existing.number} for branch ${branch}`);
      return { branch, prUrl: existing.html_url, prNumber: existing.number };
    }

    const pr = await this.api<{ html_url: string; number: number }>('POST', '/pulls', {
      title,
      head: branch,
      base,
      body,
    });

    await this.applyLabels(pr.number);

    return { branch, prUrl: pr.html_url, prNumber: pr.number };
  }

  /**
   * Resolves the commit SHA at the tip of the given branch.
   *
   * @param branch - The branch name to resolve.
   * @returns The commit SHA the branch points to.
   */
  private async getBranchSha(branch: string): Promise<string> {
    const ref = await this.api<{ object: { sha: string } }>(
      'GET',
      `/git/ref/heads/${encodeURIComponent(branch)}`,
    );
    return ref.object.sha;
  }

  /**
   * Creates the feature-branch ref, or force-updates it if it already exists.
   *
   * @param branch - The feature branch name.
   * @param sha - The commit SHA the branch should point to.
   */
  private async upsertBranchRef(branch: string, sha: string): Promise<void> {
    try {
      await this.api('POST', '/git/refs', { ref: `refs/heads/${branch}`, sha });
    } catch {
      await this.api('PATCH', `/git/refs/heads/${encodeURIComponent(branch)}`, {
        sha,
        force: true,
      });
    }
  }

  /**
   * Returns the open pull request whose head is the given branch, if any.
   *
   * @param branch - The feature branch name.
   * @returns The open PR, or `null` when none exists.
   */
  private async findOpenPr(branch: string): Promise<{ html_url: string; number: number } | null> {
    const owner = getSettings().githubRepo.split('/')[0];
    const prs = await this.api<Array<{ html_url: string; number: number }>>(
      'GET',
      `/pulls?state=open&head=${encodeURIComponent(`${owner}:${branch}`)}`,
    );
    return prs?.[0] ?? null;
  }

  /**
   * Ensures the standard labels exist and applies them to the pull request.
   * Labelling is best-effort and never fails PR creation.
   *
   * @param prNumber - The pull request number to label.
   */
  private async applyLabels(prNumber: number): Promise<void> {
    for (const label of PR_LABELS) {
      try {
        await this.api('POST', '/labels', label);
      } catch {
        // Label already exists (HTTP 422) — safe to ignore.
      }
    }

    try {
      await this.api('POST', `/issues/${prNumber}/labels`, {
        labels: PR_LABELS.map((label) => label.name),
      });
    } catch (error) {
      this.logger.warn(
        `Failed to apply labels to PR #${prNumber}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /**
   * Renders the pull request body summarising the approved tenant request.
   *
   * @param meta - The tenant request metadata.
   * @param files - The committed tfvars files.
   * @returns A Markdown string for the PR body.
   */
  private buildPrBody(meta: TenantPrMeta, files: TenantPrFile[]): string {
    const services =
      Object.entries(meta.services ?? {})
        .filter(([, enabled]) => enabled)
        .map(([name]) => name)
        .join(', ') || 'none';
    const models = (meta.modelFamilies ?? []).join(', ') || 'none';
    return [
      '## AI Services Hub — Tenant onboarding',
      '',
      `**Tenant:** ${meta.displayName} (\`${meta.projectName}\`)`,
      `**Ministry:** ${meta.ministry}${meta.department ? ` / ${meta.department}` : ''}`,
      `**Version:** ${meta.version}`,
      `**Submitted by:** ${meta.submittedBy}`,
      `**Approved by:** ${meta.approvedBy}`,
      '',
      '### Services',
      `- ${services}`,
      '',
      '### OpenAI model families',
      `- ${models}`,
      `- Capacity tier: ${meta.capacityTier || 'n/a'}`,
      '',
      ...(meta.reviewNotes ? ['### Review notes', meta.reviewNotes, ''] : []),
      '### Generated tfvars',
      ...files.map((file) => `- \`${file.path}\``),
      '',
      '> Opened automatically by the AI Services Hub Tenant Portal when the request was approved.',
    ].join('\n');
  }

  /**
   * Issues a GitHub REST API request scoped to the configured repository.
   *
   * @template T - The expected JSON response shape.
   * @param method - The HTTP method.
   * @param path - The repository-relative API path (e.g. `/pulls`).
   * @param body - Optional JSON request body.
   * @returns The parsed JSON response, or `undefined` for empty responses.
   * @throws Error when the response status is not in the 2xx range.
   */
  private async api<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
    const settings = getSettings();
    const url = `${settings.githubApiUrl}/repos/${settings.githubRepo}${path}`;
    const response = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${settings.githubToken}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'ai-services-hub-tenant-portal',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    const text = await response.text();
    if (!response.ok) {
      throw new Error(`GitHub ${method} ${path} failed (${response.status}): ${text}`);
    }

    return (text ? JSON.parse(text) : undefined) as T;
  }
}
