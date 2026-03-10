import { beforeEach, expect, test } from 'vitest';

import { TenantStoreService } from '../src/storage/tenant-store.service';

beforeEach(() => {
  process.env.PORTAL_TABLE_STORAGE_CONNECTION_STRING = '';
  process.env.PORTAL_TABLE_STORAGE_ACCOUNT_URL = '';
  TenantStoreService.resetInMemoryStore();
});

test('create and retrieve tenant versions', async () => {
  const store = new TenantStoreService();
  const version = await store.createRequest(
    'test-tenant',
    'Test Tenant',
    { ministry: 'CITZ', project_name: 'test-tenant' },
    { dev: '...', test: '...', prod: '...' },
    'user@gov.bc.ca',
  );

  expect(version).toBe('v1');

  const current = await store.getCurrent('test-tenant');
  expect(current).toBeTruthy();
  expect(current?.DisplayName).toBe('Test Tenant');
  expect(current?.Status).toBe('submitted');
});

test('versioning increments across submissions', async () => {
  const store = new TenantStoreService();
  const v1 = await store.createRequest('proj', 'Project', {}, {}, 'a@gov.bc.ca');
  const v2 = await store.createRequest('proj', 'Project Updated', {}, {}, 'a@gov.bc.ca');

  expect(v1).toBe('v1');
  expect(v2).toBe('v2');

  const current = await store.getCurrent('proj');
  expect(current).toBeTruthy();
  expect(current?.RowKey).toBe('v2');
  expect(current?.DisplayName).toBe('Project Updated');
});
