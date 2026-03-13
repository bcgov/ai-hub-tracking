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

test('listByUser returns records submitted by that email', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A', {}, {}, 'alice@gov.bc.ca');
  await store.createRequest('tenant-b', 'Tenant B', {}, {}, 'bob@gov.bc.ca');
  await store.createRequest('tenant-c', 'Tenant C', {}, {}, 'alice@gov.bc.ca');

  const aliceRecords = await store.listByUser('alice@gov.bc.ca');
  expect(aliceRecords).toHaveLength(2);
  expect(aliceRecords.map((r) => r.PartitionKey).sort()).toEqual(['tenant-a', 'tenant-c']);

  const bobRecords = await store.listByUser('bob@gov.bc.ca');
  expect(bobRecords).toHaveLength(1);
  expect(bobRecords[0].PartitionKey).toBe('tenant-b');
});

test('listByUser is case-insensitive on email', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-x', 'Tenant X', {}, {}, 'Alice@GOV.BC.CA');

  const results = await store.listByUser('alice@gov.bc.ca');
  expect(results).toHaveLength(1);
  expect(results[0].PartitionKey).toBe('tenant-x');
});

test('listByUser returns empty array for unknown email', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A', {}, {}, 'alice@gov.bc.ca');

  const results = await store.listByUser('nobody@gov.bc.ca');
  expect(results).toHaveLength(0);
});

test('listByUser includes all versions for the same tenant', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A v1', {}, {}, 'alice@gov.bc.ca');
  await store.createRequest('tenant-a', 'Tenant A v2', {}, {}, 'alice@gov.bc.ca');

  const results = await store.listByUser('alice@gov.bc.ca');
  expect(results).toHaveLength(2);
  expect(results.map((r) => r.RowKey).sort()).toEqual(['v1', 'v2']);
});

test('resetInMemoryStore clears user index', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A', {}, {}, 'alice@gov.bc.ca');
  expect(await store.listByUser('alice@gov.bc.ca')).toHaveLength(1);

  TenantStoreService.resetInMemoryStore();
  // New store instance after reset to reflect cleared state
  const freshStore = new TenantStoreService();
  expect(await freshStore.listByUser('alice@gov.bc.ca')).toHaveLength(0);
});

test('listByStatus returns records with matching status', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A', {}, {}, 'alice@gov.bc.ca');
  await store.createRequest('tenant-b', 'Tenant B', {}, {}, 'bob@gov.bc.ca');

  const submitted = await store.listByStatus('submitted');
  expect(submitted).toHaveLength(2);

  await store.updateStatus('tenant-a', 'v1', 'approved', 'admin@gov.bc.ca');

  const stillSubmitted = await store.listByStatus('submitted');
  expect(stillSubmitted).toHaveLength(1);
  expect(stillSubmitted[0].PartitionKey).toBe('tenant-b');

  const approved = await store.listByStatus('approved');
  expect(approved).toHaveLength(1);
  expect(approved[0].PartitionKey).toBe('tenant-a');
});

test('listByStatus returns empty for unknown status', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A', {}, {}, 'alice@gov.bc.ca');

  const results = await store.listByStatus('rejected');
  expect(results).toHaveLength(0);
});

test('listAccessibleByUser returns tenants where user is submitter', async () => {
  const store = new TenantStoreService();
  await store.createRequest('tenant-a', 'Tenant A', {}, {}, 'alice@gov.bc.ca');
  await store.createRequest('tenant-b', 'Tenant B', {}, {}, 'bob@gov.bc.ca');

  const accessible = await store.listAccessibleByUser('alice@gov.bc.ca');
  expect(accessible).toHaveLength(1);
  expect(accessible[0].PartitionKey).toBe('tenant-a');
});

test('listAccessibleByUser returns tenants where user is admin', async () => {
  const store = new TenantStoreService();
  await store.createRequest(
    'tenant-a',
    'Tenant A',
    { admin_users: ['charlie@gov.bc.ca'] },
    {},
    'alice@gov.bc.ca',
  );

  const charlieAccess = await store.listAccessibleByUser('charlie@gov.bc.ca');
  expect(charlieAccess).toHaveLength(1);
  expect(charlieAccess[0].PartitionKey).toBe('tenant-a');
});

test('listAccessibleByUser is case-insensitive on email', async () => {
  const store = new TenantStoreService();
  await store.createRequest(
    'tenant-a',
    'Tenant A',
    { admin_users: ['Charlie@GOV.BC.CA'] },
    {},
    'alice@gov.bc.ca',
  );

  const accessible = await store.listAccessibleByUser('charlie@gov.bc.ca');
  expect(accessible).toHaveLength(1);
});

test('listAccessibleByUser removes stale access on version update', async () => {
  const store = new TenantStoreService();
  await store.createRequest(
    'tenant-a',
    'Tenant A',
    { admin_users: ['charlie@gov.bc.ca'] },
    {},
    'alice@gov.bc.ca',
  );

  expect(await store.listAccessibleByUser('charlie@gov.bc.ca')).toHaveLength(1);

  // Create v2 without charlie in admin_users
  await store.createRequest('tenant-a', 'Tenant A v2', { admin_users: [] }, {}, 'alice@gov.bc.ca');

  expect(await store.listAccessibleByUser('charlie@gov.bc.ca')).toHaveLength(0);
  expect(await store.listAccessibleByUser('alice@gov.bc.ca')).toHaveLength(1);
});

test('resetInMemoryStore clears status and access indexes', async () => {
  const store = new TenantStoreService();
  await store.createRequest(
    'tenant-a',
    'Tenant A',
    { admin_users: ['charlie@gov.bc.ca'] },
    {},
    'alice@gov.bc.ca',
  );
  expect(await store.listByStatus('submitted')).toHaveLength(1);
  expect(await store.listAccessibleByUser('alice@gov.bc.ca')).toHaveLength(1);

  TenantStoreService.resetInMemoryStore();
  const freshStore = new TenantStoreService();
  expect(await freshStore.listByStatus('submitted')).toHaveLength(0);
  expect(await freshStore.listAccessibleByUser('alice@gov.bc.ca')).toHaveLength(0);
});
