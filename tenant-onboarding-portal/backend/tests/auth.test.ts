import { expect, test } from 'vitest';

import request from 'supertest';

import { createTestApp } from './helpers/test-app';

test('oidc mode rejects requests without a session', async () => {
  const app = await createTestApp({ authMode: 'oidc' });

  try {
    const response = await request(app.getHttpServer()).get('/api/form-schema');
    expect(response.status).toBe(401);
    expect(response.body.message).toBe('Authentication required');
  } finally {
    await app.close();
  }
});

test('mock auth auto-establishes an admin session', async () => {
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    const response = await agent.get('/api/session');

    expect(response.status).toBe(200);
    expect(response.body.authenticated).toBe(true);
    expect(response.body.isAdmin).toBe(true);
    expect(response.body.user.email).toBe('dev.user@gov.bc.ca');
    expect(response.body.user.roles).toEqual(['portal-admin']);
    expect(response.headers['set-cookie']?.join(';')).toContain('tenant-portal-session=');
  } finally {
    await app.close();
  }
});

test('create tenant api returns persisted detail', async () => {
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());

    const createResponse = await agent.post('/api/tenants').send({
      project_name: 'alpha-demo',
      display_name: 'Alpha Demo',
      ministry: 'CITZ',
      department: 'Digital Office',
      admin_emails: ['owner@gov.bc.ca'],
    });

    expect(createResponse.status).toBe(201);
    expect(createResponse.body.tenant.DisplayName).toBe('Alpha Demo');

    const detailResponse = await agent.get('/api/tenants/alpha-demo');

    expect(detailResponse.status).toBe(200);
    expect(detailResponse.body.tenant.DisplayName).toBe('Alpha Demo');
  } finally {
    await app.close();
  }
});

test('form schema exposes defaults and validation metadata', async () => {
  const app = await createTestApp();

  try {
    const agent = request.agent(app.getHttpServer());
    const response = await agent.get('/api/form-schema');

    expect(response.status).toBe(200);
    expect(response.body.defaults.ministry).toBe(response.body.ministries[0]);
    expect(response.body.defaults.form_version).toBe(response.body.version);
    expect(response.body.field_info.project_name.label).toBe('Project name');
    expect(response.body.validation.project_name.pattern).toBe('^[a-z0-9][a-z0-9-]*[a-z0-9]$');
    expect(response.body.validation.primary_services.require_at_least_one_of).toEqual([
      'openai_enabled',
      'document_intelligence_enabled',
    ]);
  } finally {
    await app.close();
  }
});
