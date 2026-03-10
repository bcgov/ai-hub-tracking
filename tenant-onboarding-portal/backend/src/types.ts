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
