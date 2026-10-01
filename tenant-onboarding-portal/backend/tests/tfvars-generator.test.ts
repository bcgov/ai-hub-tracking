import { expect, test } from 'vitest';

import { generateAllEnvTfvars } from '../src/services/tfvars-generator';
import type { TenantFormData } from '../src/types';

function sampleForm(): TenantFormData {
  return {
    project_name: 'test-project',
    display_name: 'Test Project',
    ministry: 'CITZ',
    department: 'Corporate Online Services',
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
    openai_enabled: true,
    ai_search_enabled: true,
    document_intelligence_enabled: false,
    speech_services_enabled: false,
    cosmos_db_enabled: false,
    storage_account_enabled: true,
    key_vault_enabled: false,
    model_families: ['gpt-4.1', 'embeddings'],
    capacity_tier: 'standard',
    pii_redaction_enabled: true,
    logging_enabled: true,
    custom_rai_filters_enabled: false,
    admin_users: ['alice@gov.bc.ca', 'bob@gov.bc.ca'],
    write_users: [],
    read_users: [],
  };
}

test('generates all three environments', () => {
  const result = generateAllEnvTfvars(sampleForm());
  expect(Object.keys(result).sort()).toEqual(['dev', 'prod', 'test']);
});

test('environment tags and tenant name are emitted', () => {
  const result = generateAllEnvTfvars(sampleForm());
  expect(result.dev).toMatch(/tenant_name {2}= "test-project"/);
  expect(result.dev).toMatch(/environment = "dev"/);
  expect(result.test).toMatch(/environment = "test"/);
  expect(result.prod).toMatch(/environment = "prod"/);
});
