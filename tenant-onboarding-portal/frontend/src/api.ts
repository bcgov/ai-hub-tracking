import axios from 'axios';

import type {
  AdminDashboardResponse,
  AdminReviewResponse,
  ApimTenantInfoResponse,
  FormSchema,
  HubEnv,
  SessionResponse,
  TenantCredentialsResponse,
  TenantDetailResponse,
  TenantFormPayload,
  TenantListResponse,
} from './types';

export class ApiError extends Error {
  status: number;

  /**
   * Creates a new `ApiError` with an HTTP status code and message.
   * @param status - HTTP status code returned by the server.
   * @param message - Human-readable error description.
   */
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const client = axios.create({
  baseURL: '/api',
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
});

/**
 * Executes an Axios request and returns the parsed response data.
 * Converts Axios errors into `ApiError` instances, preserving the HTTP status and server detail message.
 * @param request - Pending Axios request promise.
 * @returns Promise resolving to the typed response data.
 * @throws {ApiError} When the server returns an error response.
 */
async function requestJson<T>(request: Promise<{ data: T }>): Promise<T> {
  try {
    const response = await request;
    return response.data;
  } catch (error) {
    if (axios.isAxiosError(error)) {
      const detail =
        typeof error.response?.data?.detail === 'string' ? error.response.data.detail : undefined;
      throw new ApiError(error.response?.status ?? 500, detail ?? error.message);
    }

    throw error;
  }
}

export const api = {
  session: () => requestJson<SessionResponse>(client.get('/session')),
  formSchema: () => requestJson<FormSchema>(client.get('/form-schema')),
  listTenants: () => requestJson<TenantListResponse>(client.get('/tenants')),
  getTenant: (tenantName: string) =>
    requestJson<TenantDetailResponse>(client.get(`/tenants/${tenantName}`)),
  createTenant: (payload: TenantFormPayload) =>
    requestJson<{ tenant: TenantDetailResponse['tenant']; version: string }>(
      client.post('/tenants', payload),
    ),
  updateTenant: (tenantName: string, payload: TenantFormPayload) =>
    requestJson<{ tenant: TenantDetailResponse['tenant']; version: string }>(
      client.put(`/tenants/${tenantName}`, payload),
    ),
  adminDashboard: () => requestJson<AdminDashboardResponse>(client.get('/admin/dashboard')),
  adminReview: (tenantName: string, version: string) =>
    requestJson<AdminReviewResponse>(client.get(`/admin/review/${tenantName}/${version}`)),
  approveRequest: (tenantName: string, version: string, reviewNotes: string) =>
    requestJson<{ status: string }>(
      client.post(`/admin/approve/${tenantName}/${version}`, {
        review_notes: reviewNotes,
      }),
    ),
  rejectRequest: (tenantName: string, version: string, reviewNotes: string) =>
    requestJson<{ status: string }>(
      client.post(`/admin/reject/${tenantName}/${version}`, {
        review_notes: reviewNotes,
      }),
    ),
  getCredentials: (tenantName: string, env: HubEnv) =>
    requestJson<TenantCredentialsResponse>(
      client.get(`/tenants/${tenantName}/credentials`, { params: { env } }),
    ),
  getApimTenantInfo: (tenantName: string, env: HubEnv) =>
    requestJson<ApimTenantInfoResponse>(
      client.get(`/tenants/${tenantName}/tenant-info`, { params: { env } }),
    ),
};
