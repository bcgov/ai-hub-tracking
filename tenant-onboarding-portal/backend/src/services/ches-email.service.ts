import { Injectable, Logger } from '@nestjs/common';

import { getSettings } from '../config/settings';
import type { PortalUser, TenantRecord } from '../types';

export type TenantRequestEvent = 'submitted' | 'updated';

type CachedToken = {
  accessToken: string;
  expiresAt: number;
};

/** Refresh the CHES token this many milliseconds before it actually expires. */
const TOKEN_EXPIRY_SKEW_MS = 30_000;

/**
 * Escapes a value for safe interpolation into an HTML email body.
 *
 * @param value - The raw, possibly user-supplied value.
 * @returns The HTML-escaped string.
 */
function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

@Injectable()
export class ChesEmailService {
  private readonly logger = new Logger(ChesEmailService.name);
  private cachedToken: CachedToken | null = null;

  /**
   * Indicates whether CHES notifications are fully configured. Notifications are
   * silently skipped when the client credentials, sender, or admin recipients are missing.
   *
   * @returns True when all required CHES settings and at least one admin recipient are present.
   */
  isEnabled(): boolean {
    const settings = getSettings();
    return Boolean(
      settings.chesClientId &&
      settings.chesClientSecret &&
      settings.chesFromAddress &&
      settings.notificationAdminEmails.length > 0,
    );
  }

  /**
   * Notifies the configured admin recipients that a tenant request was submitted or updated.
   * Never throws: failures are logged so a CHES outage cannot fail the user's submission.
   *
   * @param event - Whether this is a new submission or an update to an existing tenant.
   * @param tenant - The current tenant record after the write.
   * @param version - The version string assigned to this request (e.g. `'v2'`).
   * @param user - The portal user who made the change.
   */
  async notifyTenantRequest(
    event: TenantRequestEvent,
    tenant: TenantRecord | null,
    version: string,
    user: PortalUser,
  ): Promise<void> {
    if (!tenant || !this.isEnabled()) {
      return;
    }

    try {
      const txId = await this.sendEmail(
        getSettings().notificationAdminEmails,
        this.buildSubject(event, tenant, version),
        this.buildBody(event, tenant, version, user),
        `tenant-request-${event}`,
      );
      this.logger.log(
        `Sent tenant request ${event} notification for ${tenant.PartitionKey}:${version} (CHES txId=${txId})`,
      );
    } catch (error) {
      this.logger.error(
        `Failed to send tenant request ${event} notification for ${tenant.PartitionKey}:${version}`,
        error instanceof Error ? error.stack : String(error),
      );
    }
  }

  /**
   * Sends an HTML email through CHES.
   *
   * @param to - The recipient email addresses.
   * @param subject - The email subject line.
   * @param body - The HTML email body.
   * @param tag - A CHES tag used to group related messages.
   * @returns The CHES transaction ID for the accepted message.
   * @throws Error when the token request or the send request fails.
   */
  async sendEmail(to: string[], subject: string, body: string, tag: string): Promise<string> {
    const settings = getSettings();
    const accessToken = await this.getAccessToken();
    const response = await fetch(`${settings.chesApiUrl}/email`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify({
        from: settings.chesFromAddress,
        to,
        cc: [],
        bcc: [],
        subject,
        bodyType: 'html',
        body,
        encoding: 'utf-8',
        priority: 'normal',
        tag,
      }),
    });

    if (response.status === 401) {
      this.cachedToken = null;
    }
    if (!response.ok) {
      throw new Error(`CHES send failed with HTTP ${response.status}: ${await response.text()}`);
    }

    const payload = (await response.json()) as { txId?: string };
    return payload.txId ?? '';
  }

  /**
   * Returns a CHES access token obtained via the client credentials grant,
   * reusing a cached token until shortly before it expires.
   *
   * @returns The bearer access token.
   * @throws Error when the token endpoint fails or returns no access token.
   */
  private async getAccessToken(): Promise<string> {
    if (this.cachedToken && this.cachedToken.expiresAt > Date.now()) {
      return this.cachedToken.accessToken;
    }

    const settings = getSettings();
    const response = await fetch(settings.chesTokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: settings.chesClientId,
        client_secret: settings.chesClientSecret,
      }),
    });
    if (!response.ok) {
      throw new Error(`CHES token request failed with HTTP ${response.status}`);
    }

    const payload = (await response.json()) as { access_token?: string; expires_in?: number };
    if (!payload.access_token) {
      throw new Error('CHES token response did not contain an access_token');
    }

    const expiresInMs = (payload.expires_in ?? 300) * 1000;
    this.cachedToken = {
      accessToken: payload.access_token,
      expiresAt: Date.now() + Math.max(expiresInMs - TOKEN_EXPIRY_SKEW_MS, 0),
    };
    return payload.access_token;
  }

  /**
   * Builds the notification subject line.
   *
   * @param event - Whether this is a new submission or an update.
   * @param tenant - The current tenant record.
   * @param version - The request version string.
   * @returns The subject line.
   */
  private buildSubject(event: TenantRequestEvent, tenant: TenantRecord, version: string): string {
    const action =
      event === 'submitted' ? 'New tenant request submitted' : 'Tenant request updated';
    return `[${getSettings().appName}] ${action}: ${tenant.DisplayName || tenant.PartitionKey} (${version})`;
  }

  /**
   * Builds the HTML notification body, escaping all tenant-supplied values.
   *
   * @param event - Whether this is a new submission or an update.
   * @param tenant - The current tenant record.
   * @param version - The request version string.
   * @param user - The portal user who made the change.
   * @returns The HTML email body.
   */
  private buildBody(
    event: TenantRequestEvent,
    tenant: TenantRecord,
    version: string,
    user: PortalUser,
  ): string {
    const settings = getSettings();
    const heading =
      event === 'submitted' ? 'A new tenant request was submitted' : 'A tenant request was updated';
    const rows: Array<[string, unknown]> = [
      ['Tenant', tenant.PartitionKey],
      ['Display name', tenant.DisplayName],
      ['Ministry', tenant.Ministry],
      ['Version', version],
      ['Status', tenant.Status],
      ['Submitted by', user.name ? `${user.name} <${user.email}>` : user.email],
      ['Submitted at', tenant.UpdatedAt ?? tenant.CreatedAt],
    ];
    const reviewLink = settings.publicBaseUrl
      ? `<p><a href="${escapeHtml(
          `${settings.publicBaseUrl}/admin/review/${encodeURIComponent(tenant.PartitionKey)}/${encodeURIComponent(version)}`,
        )}">Review this request in the portal</a></p>`
      : '';

    return [
      `<h2>${escapeHtml(heading)}</h2>`,
      '<table cellpadding="4" cellspacing="0" border="0">',
      ...rows.map(
        ([label, value]) =>
          `<tr><td><strong>${escapeHtml(label)}</strong></td><td>${escapeHtml(value)}</td></tr>`,
      ),
      '</table>',
      reviewLink,
      `<p style="color:#666;font-size:12px">Sent by ${escapeHtml(settings.appName)}.</p>`,
    ].join('\n');
  }
}
