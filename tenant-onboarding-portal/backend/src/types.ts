export type PortalUser = {
  email: string;
  name: string;
  preferred_username: string;
  roles: string[];
};

export type PortalAuthMode = 'oidc' | 'mock';

export type MockPortalUser = PortalUser & {
  accessToken: string;
};

export type PublicOidcConfig = {
  mode: PortalAuthMode;
  enabled: boolean;
  url: string;
  realm: string;
  clientId: string;
  audience: string;
  adminRole: string;
  authorizationEndpoint: string;
  endSessionEndpoint: string;
  scope: string;
  mockAccessToken: string;
};

export type OidcTokenSet = {
  accessToken: string;
  refreshToken: string;
  idToken: string;
  tokenType: string;
  expiresIn: number;
  refreshExpiresIn: number;
};

export type PortalSessionRecord = {
  id: string;
  user: PortalUser;
  accessToken: string;
  refreshToken: string;
  idToken: string;
  tokenType: string;
  createdAt: string;
  updatedAt: string;
  expiresAt: string;
};

export type PortalLoginState = {
  state: string;
  codeVerifier: string;
  redirectUri: string;
  returnTo: string;
  createdAt: string;
  expiresAt: string;
};

export type PortalRedirectState = {
  state: string;
  returnTo: string;
  createdAt: string;
  expiresAt: string;
};

export type PortalSettings = {
  appName: string;
  debug: boolean;
  authMode: PortalAuthMode;
  corsAllowedOrigins: string[];
  oidcDiscoveryUrl: string;
  oidcClientId: string;
  oidcClientSecret: string;
  oidcClientAudience: string;
  oidcAdminRole: string;
  mockUser: MockPortalUser;
  tableStorageConnectionString: string;
  tableStorageAccountUrl: string;
  hubKeyVaultUrlDev: string;
  hubKeyVaultUrlTest: string;
  hubKeyVaultUrlProd: string;
  apimGatewayUrlDev: string;
  apimGatewayUrlTest: string;
  apimGatewayUrlProd: string;
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
  FormVersion?: string;
  CreatedAt: string;
  UpdatedAt?: string;
};

export type TenantFormData = {
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

export interface ApimEnvCredentials {
  tenant_name: string;
  env: HubEnv;
  primary_key: string;
  secondary_key: string;
  rotation: Record<string, unknown> | null;
}

export interface RawApimTenantInfoModel {
  name: string;
  model_name?: string;
  model_version?: string;
  scale_type?: string;
  deployment?: string;
  capacity?: number;
  capacity_unit?: string;
  capacity_k_tpm?: number;
  input_tpm_per_ptu?: number;
  output_tokens_to_input_ratio?: number;
  token_limit_strategy?: 'raw_tokens_per_minute' | 'response_weighted_actual_tokens';
  prompt_tokens_weight?: number;
  completion_tokens_weight?: number;
  weighted_tokens_per_minute?: number;
  apim_raw_tokens_per_minute?: number;
  input_equivalent_tokens_per_minute?: number;
  tokens_per_minute?: number;
  endpoints?: {
    azure_openai?: {
      api_version?: string;
      endpoint?: string;
      url?: string;
    };
    openai_compatible?: {
      base_url?: string;
      model?: string;
      url?: string;
    };
  };
}

export interface RawApimTenantInfoService {
  enabled: boolean;
  [key: string]: unknown;
}

export interface RawApimTenantInfoResponse {
  tenant: string;
  base_url: string;
  models: RawApimTenantInfoModel[];
  services: Record<string, RawApimTenantInfoService>;
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
