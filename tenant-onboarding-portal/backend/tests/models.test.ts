import { expect, test } from 'vitest';

import { parseTenantForm } from '../src/models/tenant-form';

const BUSINESS_CONTEXT = {
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

test('valid tenant form uses defaults', () => {
  const data = parseTenantForm({
    project_name: 'my-test-project',
    ...BUSINESS_CONTEXT,
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
      ...BUSINESS_CONTEXT,
      display_name: 'X',
      ministry: 'CITZ',
    }),
  ).toThrow(/Project name must be lowercase/);
});

test('invalid email domains are rejected', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      ...BUSINESS_CONTEXT,
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
      ...BUSINESS_CONTEXT,
      display_name: '   ',
      ministry: 'CITZ',
    }),
  ).toThrow(/Display name is required/);
});

test('invalid ministries are rejected', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      ...BUSINESS_CONTEXT,
      display_name: 'Valid',
      ministry: 'INVALID',
    }),
  ).toThrow(/Select a ministry/);
});

test('openai requests require at least one model family', () => {
  expect(() =>
    parseTenantForm({
      project_name: 'valid-name',
      ...BUSINESS_CONTEXT,
      display_name: 'Valid',
      ministry: 'CITZ',
      openai_enabled: true,
      document_intelligence_enabled: false,
      model_families: [],
    }),
  ).toThrow(/model families/i);
});

test('business context fields are trimmed and stored', () => {
  const data = parseTenantForm({
    ...BUSINESS_CONTEXT,
    project_name: 'valid-name',
    display_name: 'Valid',
    ministry: 'CITZ',
    business_need: '  Need  ',
    data_classification: 'Sensitive / Confidential',
  });

  expect(data.business_need).toBe('Need');
  expect(data.executive_sponsor_name).toBe('Jane Doe');
  expect(data.delivery_owner_title).toBe('Product Owner');
  expect(data.data_classification).toBe('Sensitive / Confidential');
});

test.each([
  ['business_need', /Business need is required/],
  ['desired_outcome', /Desired outcome is required/],
  ['executive_sponsor_name', /Executive sponsor name is required/],
  ['executive_sponsor_title', /Executive sponsor title is required/],
  ['executive_sponsor_email', /Executive sponsor email must be a valid @gov.bc.ca/],
  ['delivery_owner_name', /Delivery owner name is required/],
  ['delivery_owner_title', /Delivery owner title is required/],
  ['delivery_owner_email', /Delivery owner email must be a valid @gov.bc.ca/],
  ['intended_users_use_case', /Intended users and use case/],
])('missing %s is rejected', (field, message) => {
  expect(() =>
    parseTenantForm({
      ...BUSINESS_CONTEXT,
      [field]: '   ',
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'CITZ',
    }),
  ).toThrow(message);
});

test('overlong business context text is rejected', () => {
  expect(() =>
    parseTenantForm({
      ...BUSINESS_CONTEXT,
      business_need: 'x'.repeat(2001),
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'CITZ',
    }),
  ).toThrow(/Business need/);
});

test.each([[''], ['Top Secret']])('invalid data classification %j is rejected', (value) => {
  expect(() =>
    parseTenantForm({
      ...BUSINESS_CONTEXT,
      data_classification: value,
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'CITZ',
    }),
  ).toThrow(/data classification/);
});

test.each([
  ['executive_sponsor_email', 'jane.doe@gmail.com'],
  ['executive_sponsor_email', 'jane doe@gov.bc.ca'],
  ['delivery_owner_email', 'john@gov.bc.ca.evil.com'],
  ['delivery_owner_email', 'not-an-email'],
])('non-government contact email %s=%j is rejected', (field, value) => {
  expect(() =>
    parseTenantForm({
      ...BUSINESS_CONTEXT,
      [field]: value,
      project_name: 'valid-name',
      display_name: 'Valid',
      ministry: 'CITZ',
    }),
  ).toThrow(/@gov.bc.ca/);
});

test('contact emails are trimmed and lowercased', () => {
  const data = parseTenantForm({
    ...BUSINESS_CONTEXT,
    executive_sponsor_email: '  Jane.Doe@GOV.BC.CA ',
    project_name: 'valid-name',
    display_name: 'Valid',
    ministry: 'CITZ',
  });

  expect(data.executive_sponsor_email).toBe('jane.doe@gov.bc.ca');
});
