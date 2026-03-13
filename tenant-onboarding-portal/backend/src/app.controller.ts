import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  ForbiddenException,
  Get,
  Inject,
  NotFoundException,
  Param,
  Post,
  Put,
  Query,
  Req,
  Res,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { Request, Response } from 'express';

import { AuthSessionService } from './auth/session.service';
import { TokenValidatorService } from './auth/token-validator.service';
import { FORM_SCHEMA } from './models/form-schema';
import { parseTenantForm } from './models/tenant-form';
import { HubKeyVaultService } from './services/hub-keyvault.service';
import { generateAllEnvTfvars } from './services/tfvars-generator';
import { TenantStoreService } from './storage/tenant-store.service';
import { getSettings } from './config/settings';
import type {
  ApimTenantInfoModel,
  ApimTenantInfoResponse,
  HubEnv,
  PortalUser,
  RawApimTenantInfoModel,
  RawApimTenantInfoResponse,
  TenantFormData,
  TenantRecord,
} from './types';

@Controller()
export class AppController {
  /**
   * Injects the services required by all route handlers.
   *
   * @param authSession - Manages session creation, refresh, and teardown.
   * @param tokenValidator - Validates and decodes bearer tokens.
   * @param tenantStore - Provides read and write access to tenant records.
   * @param hubKeyVault - Retrieves APIM credentials from Azure Key Vault per hub environment.
   */
  constructor(
    @Inject(AuthSessionService)
    private readonly authSession: AuthSessionService,
    @Inject(TokenValidatorService)
    private readonly tokenValidator: TokenValidatorService,
    @Inject(TenantStoreService)
    private readonly tenantStore: TenantStoreService,
    @Inject(HubKeyVaultService)
    private readonly hubKeyVault: HubKeyVaultService,
  ) {}

  /**
   * Returns a simple health check response indicating the service is running.
   *
   * @returns An object with `status: 'ok'`.
   */
  @Get('healthz')
  healthz() {
    return { status: 'ok' };
  }

  /**
   * Returns the current portal session state for the authenticated user.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `authenticated`, `user`, and `isAdmin` fields.
   */
  @Get('api/session')
  async session(@Req() request: Request, @Res({ passthrough: true }) response: Response) {
    const user = await this.getOptionalUser(request, response);
    if (!user) {
      return { authenticated: false, user: null, isAdmin: false };
    }

    return {
      authenticated: true,
      user,
      isAdmin: this.tokenValidator.userHasAdminAccess(user),
    };
  }

  /**
   * Returns the public OIDC configuration required by the frontend to build login and logout URLs.
   *
   * @returns Public OIDC config (issuer, client ID, scopes, endpoints).
   */
  @Get('api/auth/config')
  authConfig() {
    return this.tokenValidator.publicConfig();
  }

  /**
   * Initiates the OIDC authorization code flow by creating a PKCE login state and
   * redirecting the user to the identity provider's authorization endpoint.
   *
   * @param request - The incoming HTTP request.
   * @param response - The outgoing HTTP response used to set the state cookie and redirect.
   * @param returnTo - Optional URL to return to after successful login.
   */
  @Get('api/auth/login')
  async login(
    @Req() request: Request,
    @Res() response: Response,
    @Query('return_to') returnTo?: string,
  ) {
    await this.authSession.beginLogin(request, response, returnTo);
  }

  /**
   * Handles the OIDC redirect callback from the identity provider. Exchanges the
   * authorization code for tokens, creates a portal session, and redirects to returnTo.
   *
   * @param request - The incoming HTTP request containing the state cookie.
   * @param response - The outgoing HTTP response used to set the session cookie and redirect.
   * @param payload - The query parameters returned by the identity provider (code, state, or error).
   */
  @Get('api/auth/callback')
  async loginCallback(
    @Req() request: Request,
    @Res() response: Response,
    @Query()
    payload:
      | {
          code?: string;
          state?: string;
          error?: string;
          error_description?: string;
        }
      | undefined,
  ) {
    await this.authSession.completeLogin(request, response, payload);
  }

  /**
   * Logs out the current user by deleting the portal session, clearing the session cookie,
   * and redirecting to the OIDC end-session endpoint.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to clear the session cookie and redirect.
   * @param returnTo - Optional URL to return to after logout completes.
   */
  @Get('api/auth/logout')
  async logout(
    @Req() request: Request,
    @Res() response: Response,
    @Query('return_to') returnTo?: string,
  ) {
    await this.authSession.logout(request, response, returnTo);
  }

  /**
   * Returns the static form schema that drives the tenant onboarding form on the frontend.
   * Requires an active portal session.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns The FORM_SCHEMA object with field definitions, validation rules, and allowed values.
   */
  @Get('api/form-schema')
  async formSchema(@Req() request: Request, @Res({ passthrough: true }) response: Response) {
    await this.requireLogin(request, response);
    return FORM_SCHEMA;
  }

  /**
   * Lists all current tenant versions submitted by the authenticated user.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with an `items` array of the user's tenant records.
   */
  @Get('api/tenants')
  async listTenants(@Req() request: Request, @Res({ passthrough: true }) response: Response) {
    const user = await this.requireLogin(request, response);
    return { items: await this.tenantStore.listAccessibleByUser(user.email) };
  }

  /**
   * Creates a new tenant onboarding request at version 1. Parses and validates the
   * request body, generates Terraform variable files for all environments, and persists
   * the record to the store.
   *
   * @param payload - The raw request body containing tenant form fields.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with the created `tenant` record and the initial `version` entry.
   * @throws If the payload fails validation or the user is not authenticated.
   */
  @Post('api/tenants')
  async createTenant(
    @Body() payload: unknown,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireLogin(request, response);
    const tenantForm = parseTenantForm(payload);
    const tfvars = generateAllEnvTfvars(tenantForm);
    const version = await this.tenantStore.createRequest(
      tenantForm.project_name,
      tenantForm.display_name,
      tenantForm as unknown as Record<string, unknown>,
      tfvars,
      user.email,
    );
    const tenant = await this.tenantStore.getCurrent(tenantForm.project_name);
    return { tenant, version };
  }

  /**
   * Returns the current version and full version history for the given tenant.
   * Only the submitting user or an admin may access the record.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with the `tenant` record and a `versions` array.
   * @throws NotFoundException when the tenant does not exist.
   * @throws ForbiddenException when the user is neither the submitter nor an admin.
   */
  @Get('api/tenants/:tenantName')
  async getTenant(
    @Param('tenantName') tenantName: string,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireLogin(request, response);
    const tenant = await this.tenantStore.getCurrent(tenantName);
    if (!tenant) {
      throw new NotFoundException('Tenant not found');
    }
    if (
      tenant.SubmittedBy !== user.email &&
      !this.tokenValidator.userHasAdminAccess(user) &&
      !this.userIsTenantAdmin(user.email, tenant)
    ) {
      throw new ForbiddenException('Access denied');
    }

    return {
      tenant,
      versions: await this.tenantStore.listVersions(tenantName),
    };
  }

  /**
   * Creates a new version of an existing tenant request with updated form data.
   * Regenerates Terraform variable files and appends the new version to the store.
   * Only the original submitter or an admin may update a tenant.
   *
   * @param tenantName - The partition key / project name of the tenant to update.
   * @param payload - The raw request body containing the updated tenant form fields.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with the updated `tenant` record and the new `version` entry.
   * @throws ForbiddenException when the user is neither the original submitter nor an admin.
   */
  @Put('api/tenants/:tenantName')
  async updateTenant(
    @Param('tenantName') tenantName: string,
    @Body() payload: unknown,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireLogin(request, response);
    const existing = await this.tenantStore.getCurrent(tenantName);
    if (
      existing &&
      existing.SubmittedBy !== user.email &&
      !this.tokenValidator.userHasAdminAccess(user)
    ) {
      throw new ForbiddenException('Access denied');
    }
    const tenantForm = parseTenantForm(payload);
    const tfvars = generateAllEnvTfvars(tenantForm);
    const version = await this.tenantStore.createRequest(
      tenantName,
      tenantForm.display_name,
      tenantForm as unknown as Record<string, unknown>,
      tfvars,
      user.email,
    );
    const tenant = await this.tenantStore.getCurrent(tenantName);
    return { tenant, version };
  }

  /**
   * Returns the admin dashboard data: all currently pending submissions and the
   * latest version of every tenant in the system. Requires admin access.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `pending` submissions and `all_tenants` current versions.
   */
  @Get('api/admin/dashboard')
  async adminDashboard(@Req() request: Request, @Res({ passthrough: true }) response: Response) {
    await this.requireAdmin(request, response);
    return {
      pending: await this.tenantStore.listByStatus('submitted'),
      all_tenants: await this.tenantStore.listAllCurrent(),
    };
  }

  /**
   * Returns the specific tenant version record needed for an admin to perform a review.
   * Requires admin access.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier to review.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `tenant_request` containing the full version record.
   * @throws NotFoundException when the version record does not exist.
   */
  @Get('api/admin/review/:tenantName/:version')
  async adminReview(
    @Param('tenantName') tenantName: string,
    @Param('version') version: string,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    await this.requireAdmin(request, response);
    const tenantRequest = await this.tenantStore.getVersion(tenantName, version);
    if (!tenantRequest) {
      throw new NotFoundException('Request not found');
    }

    return { tenant_request: tenantRequest };
  }

  /**
   * Approves a tenant version, setting its status to `approved` and recording
   * the reviewing admin's email and any review notes. Requires admin access.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier to approve.
   * @param payload - Optional request body containing `review_notes`.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `status: 'approved'`.
   */
  @Post('api/admin/approve/:tenantName/:version')
  async approveRequest(
    @Param('tenantName') tenantName: string,
    @Param('version') version: string,
    @Body() payload: { review_notes?: string } | undefined,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireAdmin(request, response);
    await this.tenantStore.updateStatus(
      tenantName,
      version,
      'approved',
      user.email,
      payload?.review_notes ?? '',
    );
    return { status: 'approved' };
  }

  /**
   * Rejects a tenant version, setting its status to `rejected` and recording
   * the reviewing admin's email and any review notes. Requires admin access.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier to reject.
   * @param payload - Optional request body containing `review_notes`.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `status: 'rejected'`.
   */
  @Post('api/admin/reject/:tenantName/:version')
  async rejectRequest(
    @Param('tenantName') tenantName: string,
    @Param('version') version: string,
    @Body() payload: { review_notes?: string } | undefined,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireAdmin(request, response);
    await this.tenantStore.updateStatus(
      tenantName,
      version,
      'rejected',
      user.email,
      payload?.review_notes ?? '',
    );
    return { status: 'rejected' };
  }

  /**
   * Returns the APIM primary/secondary keys and rotation metadata for an approved tenant.
   *
   * @param tenantName - Route parameter identifying the tenant.
   * @param env - Query parameter specifying the hub environment (`dev`, `test`, or `prod`).
   * @param request - The incoming HTTP request used to authenticate the caller.
   * @param response - The outgoing HTTP response used to set cache-control headers.
   * @returns The {@link ApimEnvCredentials} for the requested environment.
   */
  @Get('api/tenants/:tenantName/credentials')
  async getTenantCredentials(
    @Param('tenantName') tenantName: string,
    @Query('env') env: string,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireLogin(request, response);
    const tenant = await this.tenantStore.getCurrent(tenantName);
    if (!tenant) throw new NotFoundException('Tenant not found');
    const isAdmin = this.tokenValidator.userHasAdminAccess(user);
    if (
      !isAdmin &&
      tenant.SubmittedBy !== user.email &&
      !this.userIsTenantAdmin(user.email, tenant)
    ) {
      throw new ForbiddenException('Access denied');
    }
    if (tenant.Status !== 'approved') throw new ConflictException('Tenant is not approved');
    const hubEnv = env as HubEnv;
    const credentials = await this.hubKeyVault.getTenantApimKeys(tenantName, hubEnv);
    if (!credentials)
      throw new ServiceUnavailableException('Credentials not available for this environment');
    (response as Response).setHeader('Cache-Control', 'no-store');
    return credentials;
  }

  /**
   * Proxies a tenant-info request to the APIM internal endpoint for the given environment.
   *
   * @param tenantName - Route parameter identifying the tenant.
   * @param env - Query parameter specifying the hub environment (`dev`, `test`, or `prod`).
   * @param request - The incoming HTTP request used to authenticate the caller.
   * @param response - The outgoing HTTP response used to forward the upstream status code.
   * @returns A normalized tenant-info payload used by the portal frontend.
   */
  @Get('api/tenants/:tenantName/tenant-info')
  async getTenantInfo(
    @Param('tenantName') tenantName: string,
    @Query('env') env: string,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireLogin(request, response);
    const tenant = await this.tenantStore.getCurrent(tenantName);
    if (!tenant) throw new NotFoundException('Tenant not found');
    const isAdmin = this.tokenValidator.userHasAdminAccess(user);
    if (
      !isAdmin &&
      tenant.SubmittedBy !== user.email &&
      !this.userIsTenantAdmin(user.email, tenant)
    ) {
      throw new ForbiddenException('Access denied');
    }
    if (tenant.Status !== 'approved') throw new ConflictException('Tenant is not approved');
    const hubEnv = env as HubEnv;
    const credentials = await this.hubKeyVault.getTenantApimKeys(tenantName, hubEnv);
    if (!credentials)
      throw new ServiceUnavailableException('APIM not configured for this environment');
    const settings = getSettings();
    const apimUrl = {
      dev: settings.apimGatewayUrlDev,
      test: settings.apimGatewayUrlTest,
      prod: settings.apimGatewayUrlProd,
    }[hubEnv];
    if (!apimUrl)
      throw new ServiceUnavailableException('APIM URL not configured for this environment');
    if (!/^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/.test(tenantName)) {
      throw new BadRequestException('Invalid tenant name');
    }
    const infoUrl = `${apimUrl}/${tenantName}/internal/tenant-info`;
    const apimResp = await fetch(infoUrl, { headers: { 'api-key': credentials.primary_key } });
    (response as Response).status(apimResp.status);
    const payload = (await apimResp.json()) as RawApimTenantInfoResponse;
    return this.normalizeTenantInfoResponse(payload);
  }

  /**
   * Normalizes the raw APIM tenant-info payload into the stable portal DTO.
   *
   * @param payload - Raw JSON returned by the upstream APIM tenant-info endpoint.
   * @returns A sanitized tenant-info response for the frontend.
   */
  private normalizeTenantInfoResponse(payload: RawApimTenantInfoResponse): ApimTenantInfoResponse {
    const models = Array.isArray(payload.models)
      ? payload.models.map((model) => this.normalizeTenantInfoModel(model))
      : [];

    const services = Object.fromEntries(
      Object.entries(payload.services ?? {}).map(([serviceName, service]) => [
        serviceName,
        { enabled: Boolean(service?.enabled) },
      ]),
    );

    return {
      tenant: payload.tenant ?? '',
      base_url: payload.base_url ?? '',
      models,
      services,
    };
  }

  /**
   * Normalizes a raw APIM model entry for portal display.
   *
   * @param model - Raw model payload returned by the upstream APIM tenant-info endpoint.
   * @returns A simplified model object with stable display fields.
   */
  private normalizeTenantInfoModel(model: RawApimTenantInfoModel): ApimTenantInfoModel {
    const deployment =
      model.deployment ?? model.name ?? model.endpoints?.openai_compatible?.model ?? 'Unknown';

    return {
      name: model.model_name ?? model.name ?? deployment,
      deployment,
      capacity: this.formatTenantInfoCapacity(model),
      scale_type: model.scale_type ?? 'Not available',
      model_version: model.model_version ?? 'Not available',
    };
  }

  /**
   * Formats APIM capacity fields into a stable user-facing string.
   *
   * @param model - Raw model payload returned by the upstream APIM tenant-info endpoint.
   * @returns Formatted capacity string.
   */
  private formatTenantInfoCapacity(model: RawApimTenantInfoModel): string {
    if (typeof model.capacity_k_tpm === 'number') {
      return `${model.capacity_k_tpm}k TPM`;
    }

    if (typeof model.tokens_per_minute === 'number') {
      return `${new Intl.NumberFormat('en-CA').format(model.tokens_per_minute)} TPM`;
    }

    if (typeof model.capacity === 'number') {
      return new Intl.NumberFormat('en-CA').format(model.capacity);
    }

    return 'Not available';
  }

  /**
   * Checks whether the given user e-mail address appears in the tenant's admin_users list.
   *
   * @param userEmail - The e-mail address of the authenticated user.
   * @param tenant - The tenant record whose form data is inspected.
   * @returns `true` if the user is listed as a tenant admin, `false` otherwise.
   */
  private userIsTenantAdmin(userEmail: string, tenant: TenantRecord): boolean {
    const adminUsers = (tenant.FormData as TenantFormData | undefined)?.admin_users ?? [];
    return adminUsers.map((e: string) => e.toLowerCase()).includes(userEmail.toLowerCase());
  }

  /**
   * Reads the portal session and returns the authenticated user if one is present.
   * Returns null without throwing when no valid session exists.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns The authenticated user, or null if the session is absent or expired.
   */
  private async getOptionalUser(request: Request, response: Response): Promise<PortalUser | null> {
    return this.authSession.getOptionalUser(request, response);
  }

  /**
   * Reads the portal session and returns the authenticated user, throwing if no
   * valid session is present.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns The authenticated user.
   * @throws UnauthorizedException when the session is absent or expired.
   */
  private async requireLogin(request: Request, response: Response): Promise<PortalUser> {
    return this.authSession.requireUser(request, response);
  }

  /**
   * Reads the portal session, verifies the user is authenticated, and confirms
   * that the user's email is in the configured admin allow-list.
   *
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns The authenticated admin user.
   * @throws UnauthorizedException when the session is absent or expired.
   * @throws ForbiddenException when the user does not have admin access.
   */
  private async requireAdmin(request: Request, response: Response): Promise<PortalUser> {
    const user = await this.requireLogin(request, response);
    if (!this.tokenValidator.userHasAdminAccess(user)) {
      throw new ForbiddenException('Admin access required');
    }

    return user;
  }
}
