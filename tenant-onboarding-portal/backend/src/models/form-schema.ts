export const FORM_VERSION = '2026.03.1';

export const MINISTRIES = [
  'AF',
  'AG',
  'CITZ',
  'ECC',
  'EMCR',
  'ENV',
  'FIN',
  'FOR',
  'GCPE',
  'HLTH',
  'IRR',
  'JEDI',
  'LBR',
  'MCF',
  'MMHA',
  'MOTI',
  'MUNI',
  'NR',
  'PSFS',
  'PSSG',
  'SDPR',
  'TACS',
  'WLRS',
];

export const MODEL_FAMILIES = {
  'gpt-4.1': {
    label: 'GPT-4.1 Series',
    models: [
      {
        name: 'gpt-4.1',
        model_name: 'gpt-4.1',
        model_version: '2025-04-14',
        scale_type: 'GlobalStandard',
        default_capacity: 300,
      },
      {
        name: 'gpt-4.1-mini',
        model_name: 'gpt-4.1-mini',
        model_version: '2025-04-14',
        scale_type: 'GlobalStandard',
        default_capacity: 1500,
      },
      {
        name: 'gpt-4.1-nano',
        model_name: 'gpt-4.1-nano',
        model_version: '2025-04-14',
        scale_type: 'GlobalStandard',
        default_capacity: 1500,
      },
    ],
  },
  'gpt-4o': {
    label: 'GPT-4o Series',
    models: [
      {
        name: 'gpt-4o',
        model_name: 'gpt-4o',
        model_version: '2024-11-20',
        scale_type: 'GlobalStandard',
        default_capacity: 300,
      },
      {
        name: 'gpt-4o-mini',
        model_name: 'gpt-4o-mini',
        model_version: '2024-07-18',
        scale_type: 'GlobalStandard',
        default_capacity: 1500,
      },
    ],
  },
  'gpt-5': {
    label: 'GPT-5 Series',
    models: [
      {
        name: 'gpt-5-mini',
        model_name: 'gpt-5-mini',
        model_version: '2025-08-07',
        scale_type: 'GlobalStandard',
        default_capacity: 100,
      },
      {
        name: 'gpt-5-nano',
        model_name: 'gpt-5-nano',
        model_version: '2025-08-07',
        scale_type: 'GlobalStandard',
        default_capacity: 1500,
      },
    ],
  },
  'gpt-5.1': {
    label: 'GPT-5.1 Series',
    models: [
      {
        name: 'gpt-5.1-chat',
        model_name: 'gpt-5.1-chat',
        model_version: '2025-11-13',
        scale_type: 'GlobalStandard',
        default_capacity: 50,
      },
      {
        name: 'gpt-5.1-codex-mini',
        model_name: 'gpt-5.1-codex-mini',
        model_version: '2025-11-13',
        scale_type: 'GlobalStandard',
        default_capacity: 100,
      },
    ],
  },
  reasoning: {
    label: 'Reasoning Models',
    models: [
      {
        name: 'o1',
        model_name: 'o1',
        model_version: '2024-12-17',
        scale_type: 'GlobalStandard',
        default_capacity: 50,
      },
      {
        name: 'o3-mini',
        model_name: 'o3-mini',
        model_version: '2025-01-31',
        scale_type: 'GlobalStandard',
        default_capacity: 50,
      },
      {
        name: 'o4-mini',
        model_name: 'o4-mini',
        model_version: '2025-04-16',
        scale_type: 'GlobalStandard',
        default_capacity: 100,
      },
    ],
  },
  embeddings: {
    label: 'Embedding Models',
    models: [
      {
        name: 'text-embedding-ada-002',
        model_name: 'text-embedding-ada-002',
        model_version: '2',
        scale_type: 'GlobalStandard',
        default_capacity: 100,
      },
      {
        name: 'text-embedding-3-large',
        model_name: 'text-embedding-3-large',
        model_version: '1',
        scale_type: 'GlobalStandard',
        default_capacity: 100,
      },
      {
        name: 'text-embedding-3-small',
        model_name: 'text-embedding-3-small',
        model_version: '1',
        scale_type: 'GlobalStandard',
        default_capacity: 100,
      },
    ],
  },
} as const;

export const CAPACITY_TIERS = {
  reduced: { label: 'Reduced (0.5x quota)', multiplier: 0.5 },
  standard: { label: 'Standard (1% quota)', multiplier: 1.0 },
  elevated: { label: 'Elevated (2x quota)', multiplier: 2.0 },
} as const;

export const FORM_SCHEMA = {
  version: FORM_VERSION,
  ministries: MINISTRIES,
  model_families: MODEL_FAMILIES,
  capacity_tiers: CAPACITY_TIERS,
  auth_modes: [
    { value: 'subscription_key', label: 'API Key (Subscription Key)' },
    { value: 'oauth2', label: 'OAuth2 (Azure AD JWT)' },
  ],
  defaults: {
    project_name: '',
    display_name: '',
    ministry: MINISTRIES[0],
    department: '',
    openai_enabled: true,
    ai_search_enabled: false,
    document_intelligence_enabled: false,
    speech_services_enabled: false,
    cosmos_db_enabled: false,
    storage_account_enabled: true,
    key_vault_enabled: false,
    model_families: ['gpt-4.1', 'gpt-4o', 'embeddings'],
    capacity_tier: 'standard',
    pii_redaction_enabled: true,
    logging_enabled: true,
    custom_rai_filters_enabled: false,
    admin_users: [''],
    write_users: [''],
    read_users: [''],
    form_version: FORM_VERSION,
  },
  field_info: {
    project_name: {
      label: 'Project name',
      description:
        'Stable tenant identifier used in generated tfvars, Azure naming, and request history.',
      details:
        'Use lowercase letters, numbers, and hyphens only. This value should stay stable over the life of the tenant.',
      placeholder: 'example-tenant',
    },
    display_name: {
      label: 'Display name',
      description: 'Human-friendly name shown in the portal, admin queue, and approvals.',
      details:
        'Use the team, product, or initiative name that reviewers will recognize immediately.',
    },
    ministry: {
      label: 'Ministry',
      description: 'Owning ministry used for tagging, routing, and reporting across environments.',
      details:
        'Choose the ministry that will own the tenant budget, policy decisions, and service approvals.',
    },
    department: {
      label: 'Department or branch',
      description: 'Operational area requesting the tenant within the selected ministry.',
      details:
        'This helps reviewers distinguish teams that share the same ministry and informs generated tagging metadata.',
    },
    openai_enabled: {
      label: 'Azure OpenAI',
      description: 'Enable Azure OpenAI deployments and model configuration for this tenant.',
      details:
        'Select this when the tenant needs LLM or embedding models. At least one of Azure OpenAI or Document Intelligence is required.',
    },
    ai_search_enabled: {
      label: 'AI Search',
      description: 'Provision Azure AI Search for retrieval and indexing workloads.',
      details:
        'Choose this when the tenant needs retrieval-augmented generation, document indexing, or semantic search workflows.',
    },
    document_intelligence_enabled: {
      label: 'Document Intelligence',
      description: 'Enable OCR and structured document extraction capabilities.',
      details:
        'Use this for form extraction, OCR pipelines, and scanned-document processing. At least one of Document Intelligence or Azure OpenAI is required.',
    },
    speech_services_enabled: {
      label: 'Speech Services',
      description: 'Enable speech-to-text, text-to-speech, and related audio processing.',
      details:
        'Select this only when the tenant needs audio or transcription workloads; it is stored in tfvars even when disabled.',
    },
    cosmos_db_enabled: {
      label: 'Cosmos DB',
      description: 'Provision a Cosmos DB account for globally distributed application data.',
      details:
        'Choose this when the tenant requires low-latency document storage beyond AI service resources.',
    },
    storage_account_enabled: {
      label: 'Storage Account',
      description: 'Provision an Azure Storage account for blobs, files, queues, or tables.',
      details:
        'Keep this enabled when the tenant needs durable storage or related service-side assets.',
    },
    key_vault_enabled: {
      label: 'Key Vault',
      description: 'Provision Azure Key Vault for secrets, keys, and certificates.',
      details:
        'Use this when the tenant needs secure secret storage or managed keys integrated with its workloads.',
    },
    capacity_tier: {
      label: 'Capacity tier',
      description: 'Quota multiplier used when generating Azure OpenAI model deployment capacity.',
      details:
        'This only affects Azure OpenAI deployments. Higher tiers request more capacity for each selected model family.',
    },
    pii_redaction_enabled: {
      label: 'PII redaction',
      description: 'Apply gateway PII screening and redaction policies to tenant traffic.',
      details:
        'Use this for workloads that may process personal or sensitive text and need gateway-side redaction protection.',
    },
    logging_enabled: {
      label: 'Logging',
      description: 'Capture tenant gateway activity for diagnostics, operations, and audit needs.',
      details:
        'Disable only when there is a clear operational reason; logging supports triage, monitoring, and evidence gathering.',
    },
    custom_rai_filters_enabled: {
      label: 'Custom RAI filters',
      description: 'Enable tenant-specific Responsible AI filtering at the gateway layer.',
      details:
        'Use this when a tenant needs additional content controls beyond the platform default protection set.',
    },
    admin_users: {
      label: 'Admin users',
      description: 'Users with full tenant administration rights.',
      details:
        'Admins can manage tenant configuration decisions and should generally be a small, accountable group.',
      placeholder: 'name@gov.bc.ca',
    },
    write_users: {
      label: 'Write users',
      description: 'Users allowed to create or update tenant-managed content and configuration.',
      details:
        'Use this for operators or application owners who need change access without full administrative ownership.',
      placeholder: 'name@gov.bc.ca',
    },
    read_users: {
      label: 'Read users',
      description: 'Users allowed to view tenant resources and outputs without modifying them.',
      details:
        'Use this for auditors, analysts, or stakeholders who need visibility but not write access.',
      placeholder: 'name@gov.bc.ca',
    },
  },
  validation: {
    project_name: {
      required: true,
      min_length: 3,
      pattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$',
      message: 'Project name must be lowercase alphanumeric with hyphens, min 3 chars',
    },
    display_name: {
      required: true,
      message: 'Display name is required',
    },
    ministry: {
      required: true,
      allowed_values: MINISTRIES,
      message: 'Select a ministry from the portal form schema',
    },
    capacity_tier: {
      required: true,
      allowed_values: Object.keys(CAPACITY_TIERS),
      message: 'Select a valid capacity tier from the portal form schema',
    },
    model_families: {
      allowed_values: Object.keys(MODEL_FAMILIES),
      message: 'Select only model families published by the portal form schema',
      min_items_when_openai_enabled: 1,
    },
    admin_users: {
      email_domain: '@gov.bc.ca',
      pattern: '^[^\\s@]+@gov\\.bc\\.ca$',
      message: 'User emails must be valid @gov.bc.ca addresses',
    },
    write_users: {
      email_domain: '@gov.bc.ca',
      pattern: '^[^\\s@]+@gov\\.bc\\.ca$',
      message: 'User emails must be valid @gov.bc.ca addresses',
    },
    read_users: {
      email_domain: '@gov.bc.ca',
      pattern: '^[^\\s@]+@gov\\.bc\\.ca$',
      message: 'User emails must be valid @gov.bc.ca addresses',
    },
    primary_services: {
      require_at_least_one_of: ['openai_enabled', 'document_intelligence_enabled'],
      message: 'Select at least one primary AI service: Azure OpenAI or Document Intelligence',
    },
  },
};
