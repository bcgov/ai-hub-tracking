import { afterEach, beforeEach, expect, test, vi } from 'vitest';

import request from 'supertest';

import { TenantStoreService } from '../src/storage/tenant-store.service';
import { createTestApp } from './helpers/test-app';

const GITHUB_ENV = {
  PORTAL_GITHUB_TOKEN: 'gh-token',
  PORTAL_GITHUB_REPO: 'bcgov/ai-hub-tracking',
  PORTAL_GITHUB_API_URL: 'https://github.example.invalid',
};

const TENANT_PAYLOAD = {
  project_name: 'alpha-demo',
  display_name: 'Alpha Demo',
  ministry: 'CITZ',
  department: 'Digital Office',
  business_need: 'Reduce manual triage of citizen enquiries',
  desired_outcome: 'Faster response times for front-line staff',
  executive_sponsor_name: 'Jane Doe',
  executive_sponsor_title: 'Assistant Deputy Minister',
  executive_sponsor_email: 'jane.doe@gov.bc.ca',
  delivery_owner_name: 'John Smith',
  delivery_owner_title: 'Product Owner',
  delivery_owner_email: 'john.smith@gov.bc.ca',
  intended_users_use_case: 'Internal staff summarising enquiries',
  data_classification: 'Internal',
};

type FetchCall = { method: string; path: string; body: Record<string, unknown> | undefined };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Stubs the GitHub REST API used by GitHubOpsService and records every call.
 */
function stubGitHub(options: { failPulls?: boolean; openPrs?: unknown[] } = {}): FetchCall[] {
  const calls: FetchCall[] = [];
  const prefix = `${GITHUB_ENV.PORTAL_GITHUB_API_URL}/repos/${GITHUB_ENV.PORTAL_GITHUB_REPO}`;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      const path = url.replace(prefix, '');
      const body = init?.body ? JSON.parse(String(init.body)) : undefined;
      calls.push({ method, path, body });

      if (method === 'GET' && path.startsWith('/git/ref/heads/')) {
        return jsonResponse({ object: { sha: 'base-sha' } });
      }
      if (method === 'GET' && path.startsWith('/git/commits/')) {
        return jsonResponse({ tree: { sha: 'base-tree' } });
      }
      if (path === '/git/blobs') return jsonResponse({ sha: `blob-${calls.length}` }, 201);
      if (path === '/git/trees') return jsonResponse({ sha: 'tree-sha' }, 201);
      if (path === '/git/commits') return jsonResponse({ sha: 'commit-sha' }, 201);
      if (path === '/git/refs') return jsonResponse({}, 201);
      if (method === 'GET' && path.startsWith('/pulls?')) {
        return jsonResponse(options.openPrs ?? []);
      }
      if (method === 'POST' && path === '/pulls') {
        return options.failPulls
          ? jsonResponse({ message: 'boom' }, 500)
          : jsonResponse(
              { html_url: 'https://github.com/bcgov/ai-hub-tracking/pull/42', number: 42 },
              201,
            );
      }
      if (path === '/labels') return jsonResponse({ message: 'exists' }, 422);
      if (path.startsWith('/issues/')) return jsonResponse([]);
      return jsonResponse({ message: `unexpected ${method} ${path}` }, 404);
    }),
  );
  return calls;
}

beforeEach(() => {
  Object.assign(process.env, GITHUB_ENV);
});

afterEach(() => {
  for (const key of Object.keys(GITHUB_ENV)) {
    delete process.env[key];
  }
  vi.unstubAllGlobals();
});

test('submitting a request does not open a pull request', async () => {
  const calls = stubGitHub();
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    const createResponse = await agent.post('/api/tenants').send(TENANT_PAYLOAD);

    expect(createResponse.status).toBe(201);
    expect(createResponse.body.tenant.PrUrl).toBe('');
    expect(calls).toHaveLength(0);
  } finally {
    await app.close();
  }
});

test('approving a request opens a pull request with the tfvars for every environment', async () => {
  const calls = stubGitHub();
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    await agent.post('/api/tenants').send(TENANT_PAYLOAD);
    await agent.post('/api/admin/start-review/alpha-demo/v1').send({});

    const approveResponse = await agent
      .post('/api/admin/approve/alpha-demo/v1')
      .send({ review_notes: 'Looks good' });

    expect(approveResponse.status).toBe(201);
    expect(approveResponse.body).toEqual({
      status: 'approved',
      pr_url: 'https://github.com/bcgov/ai-hub-tracking/pull/42',
      pr_number: 42,
    });

    const tree = calls.find((call) => call.path === '/git/trees');
    expect((tree?.body?.tree as Array<{ path: string }>).map((item) => item.path)).toEqual([
      'infra-ai-hub/params/dev/tenants/alpha-demo/tenant.tfvars',
      'infra-ai-hub/params/test/tenants/alpha-demo/tenant.tfvars',
      'infra-ai-hub/params/prod/tenants/alpha-demo/tenant.tfvars',
    ]);
    const ref = calls.find((call) => call.path === '/git/refs');
    expect(ref?.body?.ref).toBe('refs/heads/tenant/alpha-demo-v1');
    const pull = calls.find((call) => call.method === 'POST' && call.path === '/pulls');
    expect(pull?.body).toMatchObject({ head: 'tenant/alpha-demo-v1', base: 'main' });
    expect(String(pull?.body?.body)).toContain('**Approved by:** dev.user@gov.bc.ca');
    expect(String(pull?.body?.body)).toContain('Looks good');

    const detail = await agent.get('/api/tenants/alpha-demo');
    expect(detail.body.tenant.Status).toBe('approved');
    expect(detail.body.tenant.PrNumber).toBe(42);
    expect(detail.body.tenant.BranchName).toBe('tenant/alpha-demo-v1');
  } finally {
    await app.close();
  }
});

test('retrying approval after the PR was recorded reuses that pull request', async () => {
  const calls = stubGitHub();
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    await agent.post('/api/tenants').send(TENANT_PAYLOAD);
    await agent.post('/api/admin/start-review/alpha-demo/v1').send({});
    await agent.post('/api/admin/approve/alpha-demo/v1').send({});
    const callsAfterFirst = calls.length;
    // Simulate a status write that failed after the PR was opened, leaving the request in review.
    await app.get(TenantStoreService).updateStatus('alpha-demo', 'v1', 'in_review');

    const second = await agent.post('/api/admin/approve/alpha-demo/v1').send({});

    expect(second.body.pr_number).toBe(42);
    expect(calls).toHaveLength(callsAfterFirst);
  } finally {
    await app.close();
  }
});

test('an already-open pull request for the branch is reused instead of duplicated', async () => {
  const calls = stubGitHub({
    openPrs: [{ html_url: 'https://github.com/bcgov/ai-hub-tracking/pull/7', number: 7 }],
  });
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    await agent.post('/api/tenants').send(TENANT_PAYLOAD);
    await agent.post('/api/admin/start-review/alpha-demo/v1').send({});

    const approveResponse = await agent.post('/api/admin/approve/alpha-demo/v1').send({});

    expect(approveResponse.body.pr_number).toBe(7);
    expect(calls.some((call) => call.method === 'POST' && call.path === '/pulls')).toBe(false);
  } finally {
    await app.close();
  }
});

test('a GitHub failure leaves the request in review so approval can be retried', async () => {
  stubGitHub({ failPulls: true });
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    await agent.post('/api/tenants').send(TENANT_PAYLOAD);
    await agent.post('/api/admin/start-review/alpha-demo/v1').send({});

    const approveResponse = await agent.post('/api/admin/approve/alpha-demo/v1').send({});

    expect(approveResponse.status).toBe(503);
    const detail = await agent.get('/api/tenants/alpha-demo');
    expect(detail.body.tenant.Status).toBe('in_review');
    expect(detail.body.tenant.PrUrl).toBe('');
  } finally {
    await app.close();
  }
});

test('approval without GitHub configuration still approves and opens no PR', async () => {
  delete process.env.PORTAL_GITHUB_TOKEN;
  const calls = stubGitHub();
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    await agent.post('/api/tenants').send(TENANT_PAYLOAD);
    await agent.post('/api/admin/start-review/alpha-demo/v1').send({});

    const approveResponse = await agent.post('/api/admin/approve/alpha-demo/v1').send({});

    expect(approveResponse.status).toBe(201);
    expect(approveResponse.body).toEqual({ status: 'approved', pr_url: null, pr_number: null });
    expect(calls).toHaveLength(0);
  } finally {
    await app.close();
  }
});

test('review actions enforce submitted → in_review → approved | rejected', async () => {
  const calls = stubGitHub();
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    await agent.post('/api/tenants').send(TENANT_PAYLOAD);

    expect((await agent.post('/api/admin/approve/alpha-demo/v1').send({})).status).toBe(409);
    expect((await agent.post('/api/admin/reject/alpha-demo/v1').send({})).status).toBe(409);
    expect(calls).toHaveLength(0);

    const pending = await agent.get('/api/admin/dashboard');
    expect(pending.body.pending.map((item: { Status: string }) => item.Status)).toEqual([
      'submitted',
    ]);

    const startResponse = await agent
      .post('/api/admin/start-review/alpha-demo/v1')
      .send({ review_notes: 'Checking quotas' });
    expect(startResponse.status).toBe(201);
    expect(startResponse.body).toEqual({ status: 'in_review' });
    expect((await agent.post('/api/admin/start-review/alpha-demo/v1').send({})).status).toBe(409);

    const inReview = await agent.get('/api/admin/dashboard');
    expect(inReview.body.pending.map((item: { Status: string }) => item.Status)).toEqual([
      'in_review',
    ]);

    const rejectResponse = await agent.post('/api/admin/reject/alpha-demo/v1').send({});
    expect(rejectResponse.status).toBe(201);
    expect((await agent.post('/api/admin/approve/alpha-demo/v1').send({})).status).toBe(409);

    const done = await agent.get('/api/admin/dashboard');
    expect(done.body.pending).toHaveLength(0);
    expect(calls).toHaveLength(0);
  } finally {
    await app.close();
  }
});
