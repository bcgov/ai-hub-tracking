import { Injectable } from '@nestjs/common';
import { SecretClient } from '@azure/keyvault-secrets';
import { DefaultAzureCredential } from '@azure/identity';

import { getSettings } from '../config/settings';
import type { HubEnv, ApimEnvCredentials } from '../types';

@Injectable()
export class HubKeyVaultService {
  private readonly clients: Record<HubEnv, SecretClient | null>;

  /**
   * Initialises one {@link SecretClient} per hub environment using the Key Vault
   * URLs from application settings. Environments without a configured URL are set
   * to `null` and treated as unavailable at request time.
   */
  constructor() {
    const settings = getSettings();
    this.clients = {
      dev: settings.hubKeyVaultUrlDev
        ? new SecretClient(settings.hubKeyVaultUrlDev, new DefaultAzureCredential())
        : null,
      test: settings.hubKeyVaultUrlTest
        ? new SecretClient(settings.hubKeyVaultUrlTest, new DefaultAzureCredential())
        : null,
      prod: settings.hubKeyVaultUrlProd
        ? new SecretClient(settings.hubKeyVaultUrlProd, new DefaultAzureCredential())
        : null,
    };
  }

  /**
   * Retrieves APIM primary/secondary keys and optional rotation metadata for a
   * tenant from the hub's Azure Key Vault for the given environment.
   *
   * @param tenantName - The tenant partition key used as the Key Vault secret name prefix.
   * @param env - The hub environment (`dev`, `test`, or `prod`) to query.
   * @returns The APIM credentials or `null` if the environment has no Key Vault
   *   configured, the secrets do not exist, or the required values are empty.
   */
  async getTenantApimKeys(tenantName: string, env: HubEnv): Promise<ApimEnvCredentials | null> {
    const client = this.clients[env];
    if (!client) return null;
    try {
      const [primary, secondary, rotationSecret] = await Promise.all([
        client.getSecret(`${tenantName}-apim-primary-key`),
        client.getSecret(`${tenantName}-apim-secondary-key`),
        client.getSecret(`${tenantName}-apim-rotation-metadata`).catch(() => null),
      ]);
      if (!primary.value || !secondary.value) return null;
      let rotation: Record<string, unknown> | null = null;
      try {
        rotation = rotationSecret?.value
          ? (JSON.parse(rotationSecret.value) as Record<string, unknown>)
          : null;
      } catch {
        rotation = null;
      }
      return {
        tenant_name: tenantName,
        env,
        primary_key: primary.value,
        secondary_key: secondary.value,
        rotation,
      };
    } catch (err: unknown) {
      const code = (err as { code?: string }).code;
      if (code === 'SecretNotFound' || code === 'ResourceNotFound') return null;
      throw err;
    }
  }
}
