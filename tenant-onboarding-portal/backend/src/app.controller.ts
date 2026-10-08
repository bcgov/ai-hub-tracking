import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  ForbiddenException,
  Get,
  Inject,
  Logger,
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
import { ChesEmailService } from './services/ches-email.service';
import { GitHubOpsService } from './services/github-ops.service';
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
  TenantStatus,
} from './types';

@Controller()
export class AppController {
  private readonly logger = new Logger(AppController.name);

  /**
   * Injects the services required by all route handlers.
   *
   * @param authSession - Manages session creation, refresh, and teardown.
   * @param tokenValidator - Validates and decodes bearer tokens.
   * @param tenantStore - Provides read and write access to tenant records.
   * @param hubKeyVault - Retrieves APIM credentials from Azure Key Vault per hub environment.
   * @param chesEmail - Sends admin email notifications through CHES.
   * @param githubOps - Opens tenant onboarding pull requests on approval.
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
    @Inject(ChesEmailService)
    private readonly chesEmail: ChesEmailService,
    @Inject(GitHubOpsService)
    private readonly githubOps: GitHubOpsService,
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
   * Resolves an internal redirect-state token and redirects the browser to the stored target.
   *
   * @param response - The outgoing HTTP response used for the redirect.
   * @param state - The short-lived redirect-state token from the auth service.
   */
  @Get('api/auth/redirect')
  async authRedirect(@Res() response: Response, @Query('state') state?: string) {
    await this.authSession.completeRedirect(response, state);
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
   * the record to the store. Notifies the configured admin recipients by email.
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
    void this.chesEmail.notifyTenantRequest('submitted', tenant, version, user);
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
   * Regenerates Terraform variable files, appends the new version to the store, and
   * notifies the configured admin recipients by email.
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
    void this.chesEmail.notifyTenantRequest(
      existing ? 'updated' : 'submitted',
      tenant,
      version,
      user,
    );
    return { tenant, version };
  }

  /**
   * Loads a tenant version for an admin decision and ensures it is in the status
   * the decision expects, enforcing `submitted → in_review → approved | rejected`.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier.
   * @param expectedStatus - The status the version must currently have.
   * @returns The tenant version record.
   * @throws NotFoundException when the version record does not exist.
   * @throws ConflictException when the version is not in `expectedStatus`.
   */
  private async getVersionInStatus(
    tenantName: string,
    version: string,
    expectedStatus: TenantStatus,
  ): Promise<TenantRecord> {
    const record = await this.tenantStore.getVersion(tenantName, version);
    if (!record) {
      throw new NotFoundException('Request not found');
    }
    if (record.Status !== expectedStatus) {
      throw new ConflictException(
        `Request is '${record.Status}'; this action requires it to be '${expectedStatus}'.`,
      );
    }
    return record;
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
      pending: [
        ...(await this.tenantStore.listByStatus('submitted')),
        ...(await this.tenantStore.listByStatus('in_review')),
      ],
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
   * Moves a `submitted` tenant version to `in_review`, recording the reviewing
   * admin's email and any review notes. Requires admin access.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier to start reviewing.
   * @param payload - Optional request body containing `review_notes`.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `status: 'in_review'`.
   * @throws NotFoundException when the version record does not exist.
   * @throws ConflictException when the version is not `submitted`.
   */
  @Post('api/admin/start-review/:tenantName/:version')
  async startReview(
    @Param('tenantName') tenantName: string,
    @Param('version') version: string,
    @Body() payload: { review_notes?: string } | undefined,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
  ) {
    const user = await this.requireAdmin(request, response);
    await this.getVersionInStatus(tenantName, version, 'submitted');
    await this.tenantStore.updateStatus(
      tenantName,
      version,
      'in_review',
      user.email,
      payload?.review_notes ?? '',
    );
    return { status: 'in_review' };
  }

  /**
   * Approves an `in_review` tenant version, setting its status to `approved` and
   * recording the reviewing admin's email and any review notes. Requires admin access.
   *
   * When GitHub integration is configured, a pull request with the version's
   * generated tfvars is opened first; the status only changes once the PR
   * exists, so a failed approval leaves the request `in_review` and can be
   * retried. Without GitHub configuration the request is approved as before.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier to approve.
   * @param payload - Optional request body containing `review_notes`.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `status: 'approved'` and the PR URL/number when one was opened.
   * @throws NotFoundException when the version record does not exist.
   * @throws ConflictException when the version is not `in_review`.
   * @throws ServiceUnavailableException when the pull request cannot be opened.
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
    const record = await this.getVersionInStatus(tenantName, version, 'in_review');

    const reviewNotes = payload?.review_notes ?? '';
    const pr = await this.openTenantPr(record, user.email, reviewNotes);
    await this.tenantStore.updateStatus(tenantName, version, 'approved', user.email, reviewNotes);
    return { status: 'approved', pr_url: pr?.prUrl ?? null, pr_number: pr?.prNumber ?? null };
  }

  /**
   * Opens the GitHub pull request for an approved tenant version and records the
   * PR metadata on the request. A version that already has a PR keeps it.
   *
   * @param record - The tenant version being approved.
   * @param approvedBy - The email address of the approving admin.
   * @param reviewNotes - The admin's review notes, included in the PR body.
   * @returns The PR URL and number, or `null` when GitHub integration is not configured.
   * @throws ServiceUnavailableException when the pull request cannot be opened.
   */
  private async openTenantPr(
    record: TenantRecord,
    approvedBy: string,
    reviewNotes: string,
  ): Promise<{ prUrl: string; prNumber: number } | null> {
    if (record.PrUrl && record.PrNumber) {
      return { prUrl: record.PrUrl, prNumber: record.PrNumber };
    }
    if (!this.githubOps.isEnabled()) {
      this.logger.warn('GitHub integration not configured; approving without opening a PR.');
      return null;
    }

    const tenantName = record.PartitionKey;
    const version = record.RowKey;
    const form = (record.FormData ?? {}) as Partial<TenantFormData>;
    const files = Object.entries(record.GeneratedTfvars ?? {}).map(([env, content]) => ({
      path: `infra-ai-hub/params/${env}/tenants/${tenantName}/tenant.tfvars`,
      content,
    }));
    if (files.length === 0) {
      throw new ServiceUnavailableException('No generated tfvars found for this request version.');
    }

    try {
      const result = await this.githubOps.createTenantPR(
        {
          projectName: tenantName,
          displayName: record.DisplayName,
          ministry: record.Ministry,
          department: form.department,
          submittedBy: record.SubmittedBy,
          approvedBy,
          reviewNotes,
          services: {
            openai: Boolean(form.openai_enabled),
            ai_search: Boolean(form.ai_search_enabled),
            document_intelligence: Boolean(form.document_intelligence_enabled),
            speech_services: Boolean(form.speech_services_enabled),
            cosmos_db: Boolean(form.cosmos_db_enabled),
            storage_account: Boolean(form.storage_account_enabled),
            key_vault: Boolean(form.key_vault_enabled),
          },
          modelFamilies: form.model_families,
          capacityTier: form.capacity_tier,
          version,
        },
        files,
      );
      await this.tenantStore.setPrInfo(
        tenantName,
        version,
        result.prUrl,
        result.prNumber,
        result.branch,
      );
      return { prUrl: result.prUrl, prNumber: result.prNumber };
    } catch (error) {
      this.logger.error(
        `Failed to open tenant PR for ${tenantName}:${version}`,
        error instanceof Error ? error.stack : String(error),
      );
      throw new ServiceUnavailableException(
        'Failed to open the GitHub pull request. The request was not approved; please retry.',
      );
    }
  }

  /**
   * Rejects an `in_review` tenant version, setting its status to `rejected` and
   * recording the reviewing admin's email and any review notes. Requires admin access.
   *
   * @param tenantName - The partition key / project name of the tenant.
   * @param version - The row key / version identifier to reject.
   * @param payload - Optional request body containing `review_notes`.
   * @param request - The incoming HTTP request containing the session cookie.
   * @param response - The outgoing HTTP response used to refresh the session cookie.
   * @returns An object with `status: 'rejected'`.
   * @throws NotFoundException when the version record does not exist.
   * @throws ConflictException when the version is not `in_review`.
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
    await this.getVersionInStatus(tenantName, version, 'in_review');
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
    const formatter = new Intl.NumberFormat('en-CA');
    const apimRawTokensPerMinute =
      model.apim_raw_tokens_per_minute ?? model.tokens_per_minute ?? undefined;
    const inputEquivalentTokensPerMinute =
      model.input_equivalent_tokens_per_minute ?? model.tokens_per_minute ?? undefined;
    const weightedTokensPerMinute =
      model.weighted_tokens_per_minute ?? inputEquivalentTokensPerMinute ?? undefined;
    const promptTokensWeight = model.prompt_tokens_weight ?? 1;
    const completionTokensWeight =
      model.completion_tokens_weight ?? model.output_tokens_to_input_ratio ?? 1;

    if (model.capacity_unit === 'PTU' && typeof model.capacity === 'number') {
      if (
        model.token_limit_strategy === 'response_weighted_actual_tokens' &&
        typeof weightedTokensPerMinute === 'number' &&
        typeof apimRawTokensPerMinute === 'number'
      ) {
        return `${formatter.format(model.capacity)} PTU (${formatter.format(weightedTokensPerMinute)} weighted TPM, prompt x${promptTokensWeight} / completion x${completionTokensWeight}, raw fallback ${formatter.format(apimRawTokensPerMinute)} TPM)`;
      }

      if (
        typeof inputEquivalentTokensPerMinute === 'number' &&
        typeof apimRawTokensPerMinute === 'number'
      ) {
        return `${formatter.format(model.capacity)} PTU (${formatter.format(inputEquivalentTokensPerMinute)} input-equivalent TPM; APIM cap ${formatter.format(apimRawTokensPerMinute)} raw TPM)`;
      }

      if (typeof inputEquivalentTokensPerMinute === 'number') {
        return `${formatter.format(model.capacity)} PTU (${formatter.format(inputEquivalentTokensPerMinute)} input-equivalent TPM)`;
      }

      return `${formatter.format(model.capacity)} PTU`;
    }

    if (typeof model.capacity_k_tpm === 'number') {
      return `${model.capacity_k_tpm}k TPM`;
    }

    if (typeof apimRawTokensPerMinute === 'number') {
      return `${formatter.format(apimRawTokensPerMinute)} TPM`;
    }

    if (typeof model.capacity === 'number') {
      return formatter.format(model.capacity);
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
