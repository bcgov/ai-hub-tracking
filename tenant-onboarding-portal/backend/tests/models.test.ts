import { expect, test } from 'vitest';

import { parseTenantForm } from '../src/models/tenant-form';

test('valid tenant form uses defaults', () => {
  const data = parseTenantForm({
    project_name: 'my-test-project',
    display_name: 'My Test Project',
    ministry: 'CITZ',
    admin_users: ['test.user@gov.bc.ca'],
  });

  expect(data.project_name).toBe('my-test-project');
  expect(data.openai_enabled).toBe(true);
  expect(data.admin_users).toEqual(['test.user@gov.bc.ca']);
  expect(data.model_families).toEqual(['gpt-4.1', 'gpt-4o', 'embeddings']);
});

test('uppercase project names are rejected', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'MyProject',
      display_name: 'X',
      ministry: 'CITZ',
    }),
  ).toThrow(/Project name must be lowercase/);
});

test('invalid email domains are rejected', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'CITZ',
      admin_users: ['user@gmail.com'],
    }),
  ).toThrow(/@gov.bc.ca/);
});

test('blank display names are rejected', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      display_name: '   ',
      ministry: 'CITZ',
    }),
  ).toThrow(/Display name is required/);
});

test('invalid ministries are rejected', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'INVALID',
    }),
  ).toThrow(/Select a ministry/);
});

test('openai requests require at least one model family', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'CITZ',
      openai_enabled: true,
      document_intelligence_enabled: false,
      model_families: [],
    }),
  ).toThrow(/model families/i);
});
