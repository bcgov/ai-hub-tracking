export type SessionUser = {
  email: string;
  name: string;
  preferred_username: string;
  roles: string[];
};

export type SessionResponse = {
  authenticated: boolean;
  user: SessionUser | null;
  isAdmin: boolean;
};

export type AuthConfigResponse = {
  mode: 'oidc' | 'mock';
  enabled: boolean;
  url: string;
  realm: string;
  clientId: string;
  audience: string;
  adminRole: string;
  authorizationEndpoint: string;
  endSessionEndpoint: string;
  scope: string;
  mockAccessToken?: string;
};

export type ModelDefinition = {
  name: string;
  model_name: string;
  model_version: string;
  scale_type: string;
  default_capacity: number;
};

export type ModelFamily = {
  label: string;
  models: ModelDefinition[];
};

export type CapacityTier = {
  label: string;
  multiplier: number;
};

export type AuthMode = {
  value: string;
  label: string;
};

export type FormFieldInfo = {
  label: string;
  description: string;
  details: string;
  placeholder?: string;
};

export type FormFieldValidation = {
  required?: boolean;
  min_length?: number;
  pattern?: string;
  message?: string;
  allowed_values?: string[];
  min_items_when_openai_enabled?: number;
  email_domain?: string;
};

export type PrimaryServicesValidation = {
  require_at_least_one_of: string[];
  message: string;
};

export type FormSchema = {
  version: string;
  ministries: string[];
  model_families: Record<string, ModelFamily>;
  capacity_tiers: Record<string, CapacityTier>;
  auth_modes: AuthMode[];
  defaults: TenantFormPayload & { form_version?: string };
  field_info: Record<keyof TenantFormPayload, FormFieldInfo>;
  validation: {
    project_name: FormFieldValidation;
    display_name: FormFieldValidation;
    ministry: FormFieldValidation;
    capacity_tier: FormFieldValidation;
    model_families: FormFieldValidation;
    admin_users: FormFieldValidation;
    write_users: FormFieldValidation;
    read_users: FormFieldValidation;
    primary_services: PrimaryServicesValidation;
  };
};

export type TenantRecord = {
  PartitionKey: string;
  RowKey: string;
  DisplayName: string;
  Ministry: string;
  FormData?: Record<string, unknown>;
  GeneratedTfvars?: Record<string, string>;
  Status: string;
  SubmittedBy: string;
  ReviewedBy?: string;
  ReviewNotes?: string;
  CreatedAt: string;
  UpdatedAt?: string;
};

export type TenantListResponse = {
  items: TenantRecord[];
};

export type TenantDetailResponse = {
  tenant: TenantRecord;
  versions: TenantRecord[];
};

export type AdminDashboardResponse = {
  pending: TenantRecord[];
  all_tenants: TenantRecord[];
};

export type AdminReviewResponse = {
  tenant_request: TenantRecord;
};

export type TenantFormPayload = {
  project_name: string;
  display_name: string;
  ministry: string;
  department: string;
  openai_enabled: boolean;
  ai_search_enabled: boolean;
  document_intelligence_enabled: boolean;
  speech_services_enabled: boolean;
  cosmos_db_enabled: boolean;
  storage_account_enabled: boolean;
  key_vault_enabled: boolean;
  model_families: string[];
  capacity_tier: string;
  pii_redaction_enabled: boolean;
  logging_enabled: boolean;
  custom_rai_filters_enabled: boolean;
  admin_users: string[];
  write_users: string[];
  read_users: string[];
  form_version?: string;
};

export type HubEnv = 'dev' | 'test' | 'prod';

export interface TenantCredentialsResponse {
  tenant_name: string;
  env: HubEnv;
  primary_key: string;
  secondary_key: string;
  rotation: Record<string, unknown> | null;
}

export interface ApimTenantInfoModel {
  name: string;
  deployment: string;
  capacity: string;
  scale_type: string;
  model_version: string;
}

export interface ApimTenantInfoService {
  enabled: boolean;
}

export interface ApimTenantInfoResponse {
  tenant: string;
  base_url: string;
  models: ApimTenantInfoModel[];
  services: Record<string, ApimTenantInfoService>;
}
