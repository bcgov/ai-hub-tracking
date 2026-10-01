export const FORM_VERSION = '2026.10.1';

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

export const DATA_CLASSIFICATIONS = [
  'Public',
  'Internal',
  'Personal Information',
  'Sensitive / Confidential',
  'Not Yet Determined',
];

const BUSINESS_TEXT_MAX_LENGTH = 2000;
const CONTACT_TEXT_MAX_LENGTH = 200;
const OTHER_MODELS_MAX_LENGTH = 500;
const GOV_EMAIL_DOMAIN = '@gov.bc.ca';
const GOV_EMAIL_PATTERN = '^[^\\s@]+@gov\\.bc\\.ca$';

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
  data_classifications: DATA_CLASSIFICATIONS,
  auth_modes: [
    { value: 'subscription_key', label: 'API Key (Subscription Key)' },
    { value: 'oauth2', label: 'OAuth2 (Azure AD JWT)' },
  ],
  defaults: {
    project_name: '',
    display_name: '',
    ministry: MINISTRIES[0],
    department: '',
    business_need: '',
    desired_outcome: '',
    executive_sponsor_name: '',
    executive_sponsor_title: '',
    executive_sponsor_email: '',
    delivery_owner_name: '',
    delivery_owner_title: '',
    delivery_owner_email: '',
    intended_users_use_case: '',
    data_classification: '',
    openai_enabled: true,
    ai_search_enabled: false,
    document_intelligence_enabled: false,
    speech_services_enabled: false,
    cosmos_db_enabled: false,
    storage_account_enabled: true,
    key_vault_enabled: false,
    model_families: ['gpt-4.1', 'gpt-4o', 'embeddings'],
    other_models: '',
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
        'Use lowercase letters, numbers, and hyphens only. This value should stay stable over the life.',
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
        'Choose the ministry that will own the budget, policy decisions, and service approvals.',
    },
    department: {
      label: 'Department or branch',
      description: 'Operational area requesting the tenant within the selected ministry.',
      details:
        'This helps reviewers distinguish teams that share the same ministry and informs generated tagging metadata.',
    },
    business_need: {
      label: 'Business need',
      description: 'The business problem or opportunity',
      details:
        'Describe why the team needs AI Hub services and what happens today without them. Reviewers use this to confirm fit for the platform.',
    },
    desired_outcome: {
      label: 'Desired outcome',
      description: 'What success looks like',
      details:
        'Describe the measurable or observable results expected, such as time saved, improved service quality, or a new capability.',
    },
    executive_sponsor_name: {
      label: 'Sponsor name',
      description: 'Executive accountable for the initiative and its budget.',
      details: 'The executive who sponsors the work and holds expense authority.',
      placeholder: 'Jane Doe',
    },
    executive_sponsor_title: {
      label: 'Sponsor title',
      description: 'Position of the executive sponsor.',
      details: 'For example Assistant Deputy Minister or Executive Director.',
      placeholder: 'Assistant Deputy Minister',
    },
    executive_sponsor_email: {
      label: 'Sponsor email',
      description: 'Government email address for the executive sponsor.',
      details: 'Must be a @gov.bc.ca address. Used for approvals and cost notifications.',
      placeholder: 'name@gov.bc.ca',
    },
    delivery_owner_name: {
      label: 'Owner name',
      description: 'Person responsible for delivering and operating the solution.',
      details: 'The owner who will build, run, and support the workload day to day.',
      placeholder: 'John Smith',
    },
    delivery_owner_title: {
      label: 'Owner title',
      description: 'Position of the delivery and operational owner.',
      details: 'For example Product Owner or Senior Manager, Digital Delivery.',
      placeholder: 'Product Owner',
    },
    delivery_owner_email: {
      label: 'Owner email',
      description: 'Government email address for the delivery and operational owner.',
      details: 'Must be a @gov.bc.ca address. Used for operational and incident contact.',
      placeholder: 'name@gov.bc.ca',
    },
    intended_users_use_case: {
      label: 'Intended users and use case',
      description: 'Who will use the solution and how they will use it.',
      details:
        'Identify the user groups (for example internal staff or the public) and describe the main scenarios the AI services will support.',
    },
    data_classification: {
      label: 'Data classification',
      description: 'Highest classification of data that will be processed.',
      details:
        'Choose the most sensitive category of data the workload will send to AI services. Select Not Yet Determined if a privacy or security assessment is still in progress.',
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
    other_models: {
      label: 'Other models',
      description: 'Additional models not listed above, separated by commas.',
      details:
        'Request models that are not yet offered as a model family, for example GPT 5.4 or GPT 5.6. These are reviewed by the platform team and are not deployed automatically.',
      placeholder: 'GPT 5.4, GPT 5.6',
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
    business_need: {
      required: true,
      max_length: BUSINESS_TEXT_MAX_LENGTH,
      message: `Business need is required (max ${BUSINESS_TEXT_MAX_LENGTH} characters)`,
    },
    desired_outcome: {
      required: true,
      max_length: BUSINESS_TEXT_MAX_LENGTH,
      message: `Desired outcome is required (max ${BUSINESS_TEXT_MAX_LENGTH} characters)`,
    },
    executive_sponsor_name: {
      required: true,
      max_length: CONTACT_TEXT_MAX_LENGTH,
      message: `Executive sponsor name is required (max ${CONTACT_TEXT_MAX_LENGTH} characters)`,
    },
    executive_sponsor_title: {
      required: true,
      max_length: CONTACT_TEXT_MAX_LENGTH,
      message: `Executive sponsor title is required (max ${CONTACT_TEXT_MAX_LENGTH} characters)`,
    },
    executive_sponsor_email: {
      required: true,
      max_length: CONTACT_TEXT_MAX_LENGTH,
      email_domain: GOV_EMAIL_DOMAIN,
      pattern: GOV_EMAIL_PATTERN,
      message: 'Executive sponsor email must be a valid @gov.bc.ca address',
    },
    delivery_owner_name: {
      required: true,
      max_length: CONTACT_TEXT_MAX_LENGTH,
      message: `Delivery owner name is required (max ${CONTACT_TEXT_MAX_LENGTH} characters)`,
    },
    delivery_owner_title: {
      required: true,
      max_length: CONTACT_TEXT_MAX_LENGTH,
      message: `Delivery owner title is required (max ${CONTACT_TEXT_MAX_LENGTH} characters)`,
    },
    delivery_owner_email: {
      required: true,
      max_length: CONTACT_TEXT_MAX_LENGTH,
      email_domain: GOV_EMAIL_DOMAIN,
      pattern: GOV_EMAIL_PATTERN,
      message: 'Delivery owner email must be a valid @gov.bc.ca address',
    },
    intended_users_use_case: {
      required: true,
      max_length: BUSINESS_TEXT_MAX_LENGTH,
      message: `Intended users and use case is required (max ${BUSINESS_TEXT_MAX_LENGTH} characters)`,
    },
    data_classification: {
      required: true,
      allowed_values: DATA_CLASSIFICATIONS,
      message: 'Select a data classification',
    },
    other_models: {
      required: false,
      max_length: OTHER_MODELS_MAX_LENGTH,
      message: `Other models must be ${OTHER_MODELS_MAX_LENGTH} characters or fewer`,
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
