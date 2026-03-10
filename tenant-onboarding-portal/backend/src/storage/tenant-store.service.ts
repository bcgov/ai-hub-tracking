import { Injectable, Logger } from '@nestjs/common';
import { TableClient, TableEntity } from '@azure/data-tables';
import { DefaultAzureCredential } from '@azure/identity';

import { getSettings } from '../config/settings';
import type { TenantRecord } from '../types';

const REQUESTS_TABLE = 'TenantRequests';
const REGISTRY_TABLE = 'TenantRegistry';

type MemoryTables = Record<string, Record<string, Record<string, unknown>>>;

const IN_MEMORY_TABLES: MemoryTables = {
  [REQUESTS_TABLE]: {},
  [REGISTRY_TABLE]: {},
};

@Injectable()
export class TenantStoreService {
  private readonly logger = new Logger(TenantStoreService.name);
  private readonly requestsTableClient: TableClient | null;
  private readonly registryTableClient: TableClient | null;
  private readonly memory: MemoryTables;
  private ensureTablesPromise: Promise<void> | null = null;

  /**
   * Reads connection settings and initialises Azure Table Storage clients for the
   * requests and registry tables, or falls back to in-memory storage when no
   * credentials are configured.
   */
  constructor() {
    const settings = getSettings();
    if (settings.tableStorageConnectionString) {
      this.logger.log(
        `Using Azure Table Storage connection string for ${REQUESTS_TABLE} and ${REGISTRY_TABLE}`,
      );
      this.requestsTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        REQUESTS_TABLE,
      );
      this.registryTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        REGISTRY_TABLE,
      );
    } else if (settings.tableStorageAccountUrl) {
      this.logger.log(
        `Using Azure AD credential for ${REQUESTS_TABLE} and ${REGISTRY_TABLE} via ${settings.tableStorageAccountUrl}`,
      );
      const credential = new DefaultAzureCredential();
      this.requestsTableClient = new TableClient(
        settings.tableStorageAccountUrl,
        REQUESTS_TABLE,
        credential,
      );
      this.registryTableClient = new TableClient(
        settings.tableStorageAccountUrl,
        REGISTRY_TABLE,
        credential,
      );
    } else {
      this.logger.warn(
        `No Azure Table Storage configuration found for ${REQUESTS_TABLE} and ${REGISTRY_TABLE}; falling back to in-memory storage`,
      );
      this.requestsTableClient = null;
      this.registryTableClient = null;
    }

    this.memory = IN_MEMORY_TABLES;
  }

  /**
   * Clears all in-memory tenant request and registry records.
   *
   * Intended for use in tests to restore a clean state between test runs.
   */
  static resetInMemoryStore(): void {
    IN_MEMORY_TABLES[REQUESTS_TABLE] = {};
    IN_MEMORY_TABLES[REGISTRY_TABLE] = {};
  }

  /**
   * Creates a new tenant provisioning request and registers it as the current version.
   *
   * Calculates the next sequential version, writes the request entity to the requests table,
   * and upserts the registry entry so `getCurrent` returns this version.
   *
   * @param tenantName - The unique tenant identifier used as the partition key.
   * @param displayName - The human-readable display name for the tenant.
   * @param formData - The raw form submission data.
   * @param generatedTfvars - The Terraform variable values derived from the form.
   * @param submittedBy - The email address of the user who submitted the request.
   * @returns The version string assigned to the new request (e.g. `'v3'`).
   */
  async createRequest(
    tenantName: string,
    displayName: string,
    formData: Record<string, unknown>,
    generatedTfvars: Record<string, string>,
    submittedBy: string,
  ): Promise<string> {
    const nextVersion = await this.nextVersion(tenantName);
    const now = new Date().toISOString();
    const entity = {
      partitionKey: tenantName,
      rowKey: nextVersion,
      DisplayName: displayName,
      Ministry: typeof formData.ministry === 'string' ? formData.ministry : '',
      FormData: JSON.stringify(formData),
      GeneratedTfvars: JSON.stringify(generatedTfvars),
      Status: 'submitted',
      SubmittedBy: submittedBy,
      ReviewedBy: '',
      ReviewNotes: '',
      FormVersion: typeof formData.form_version === 'string' ? formData.form_version : '',
      CreatedAt: now,
      UpdatedAt: now,
    };

    const table = await this.requestsTable();
    if (table) {
      try {
        await table.upsertEntity(entity as TableEntity<Record<string, unknown>>, 'Replace');
      } catch (error) {
        this.logger.error(
          `Failed to upsert ${REQUESTS_TABLE} entity ${tenantName}:${nextVersion}`,
          error instanceof Error ? error.stack : String(error),
        );
        throw error;
      }
    } else {
      this.memory[REQUESTS_TABLE][`${tenantName}:${nextVersion}`] = entity;
    }

    await this.upsertRegistry(tenantName, nextVersion);
    return nextVersion;
  }

  /**
   * Updates the approval status and optional reviewer notes on an existing request.
   *
   * @param tenantName - The tenant partition key.
   * @param version - The specific version to update (e.g. `'v2'`).
   * @param status - The new status value (e.g. `'approved'`, `'rejected'`).
   * @param reviewedBy - Email of the reviewer; defaults to an empty string.
   * @param reviewNotes - Optional notes from the reviewer; defaults to an empty string.
   */
  async updateStatus(
    tenantName: string,
    version: string,
    status: string,
    reviewedBy = '',
    reviewNotes = '',
  ): Promise<void> {
    const now = new Date().toISOString();
    const table = await this.requestsTable();
    if (table) {
      try {
        const entity = await table.getEntity<Record<string, unknown>>(tenantName, version);
        entity.Status = status;
        entity.ReviewedBy = reviewedBy;
        entity.ReviewNotes = reviewNotes;
        entity.UpdatedAt = now;
        await table.upsertEntity(entity as TableEntity<Record<string, unknown>>, 'Replace');
      } catch (error) {
        this.logger.error(
          `Failed to update ${REQUESTS_TABLE} entity ${tenantName}:${version}`,
          error instanceof Error ? error.stack : String(error),
        );
        throw error;
      }
      return;
    }

    const key = `${tenantName}:${version}`;
    const entity = this.memory[REQUESTS_TABLE][key];
    if (entity) {
      entity.Status = status;
      entity.ReviewedBy = reviewedBy;
      entity.ReviewNotes = reviewNotes;
      entity.UpdatedAt = now;
    }
  }

  /**
   * Returns the current (latest) tenant record by looking up the registry entry.
   *
   * @param tenantName - The unique tenant identifier.
   * @returns The current {@link TenantRecord}, or `null` if no record exists.
   */
  async getCurrent(tenantName: string): Promise<TenantRecord | null> {
    const registry = await this.getRegistry(tenantName);
    if (!registry) {
      return null;
    }

    return this.getVersion(tenantName, String(registry.CurrentVersion ?? 'v1'));
  }

  /**
   * Returns the tenant record for a specific version.
   *
   * @param tenantName - The unique tenant identifier.
   * @param version - The version string to retrieve (e.g. `'v2'`).
   * @returns The matching {@link TenantRecord}, or `null` if not found.
   */
  async getVersion(tenantName: string, version: string): Promise<TenantRecord | null> {
    const table = await this.requestsTable();
    if (table) {
      try {
        const entity = await table.getEntity<Record<string, unknown>>(tenantName, version);
        return this.deserialize(entity);
      } catch (error) {
        this.logger.warn(
          `Failed to read ${REQUESTS_TABLE} entity ${tenantName}:${version}: ${error instanceof Error ? error.message : String(error)}`,
        );
        return null;
      }
    }

    const entity = this.memory[REQUESTS_TABLE][`${tenantName}:${version}`];
    return entity ? this.deserialize(entity) : null;
  }

  /**
   * Returns all versions of a tenant's provisioning requests, sorted newest-first.
   *
   * @param tenantName - The unique tenant identifier.
   * @returns An array of {@link TenantRecord} objects sorted in descending version order.
   */
  async listVersions(tenantName: string): Promise<TenantRecord[]> {
    const table = await this.requestsTable();
    if (table) {
      const entities: TenantRecord[] = [];
      const safePartition = tenantName.replace(/'/g, "''");
      for await (const entity of table.listEntities<Record<string, unknown>>({
        queryOptions: { filter: `PartitionKey eq '${safePartition}'` },
      })) {
        entities.push(this.deserialize(entity));
      }

      return entities.sort((left, right) => right.RowKey.localeCompare(left.RowKey));
    }

    return Object.entries(this.memory[REQUESTS_TABLE])
      .filter(([key]) => key.startsWith(`${tenantName}:`))
      .map(([, entity]) => this.deserialize(entity))
      .sort((left, right) => right.RowKey.localeCompare(left.RowKey));
  }

  /**
   * Returns all requests submitted by the specified user email address.
   *
   * The comparison is case-insensitive. Results are not sorted.
   *
   * @param email - The submitter's email address to filter by.
   * @returns An array of {@link TenantRecord} objects submitted by that user.
   */
  async listByUser(email: string): Promise<TenantRecord[]> {
    const emailLower = email.toLowerCase();
    const safe = emailLower.replace(/'/g, "''");
    const table = await this.requestsTable();
    if (table) {
      const entities: TenantRecord[] = [];
      for await (const entity of table.listEntities<Record<string, unknown>>({
        queryOptions: { filter: `SubmittedBy eq '${safe}'` },
      })) {
        entities.push(this.deserialize(entity));
      }

      return entities;
    }

    return Object.values(this.memory[REQUESTS_TABLE])
      .filter((entity) => String(entity.SubmittedBy ?? '').toLowerCase() === emailLower)
      .map((entity) => this.deserialize(entity));
  }

  /**
   * Returns all tenant requests that match the given status value.
   *
   * @param status - The status to filter by (e.g. `'submitted'`, `'approved'`).
   * @returns An array of {@link TenantRecord} objects with the matching status.
   */
  async listByStatus(status: string): Promise<TenantRecord[]> {
    const safe = status.replace(/'/g, "''");
    const table = await this.requestsTable();
    if (table) {
      const entities: TenantRecord[] = [];
      for await (const entity of table.listEntities<Record<string, unknown>>({
        queryOptions: { filter: `Status eq '${safe}'` },
      })) {
        entities.push(this.deserialize(entity));
      }

      return entities;
    }

    return Object.values(this.memory[REQUESTS_TABLE])
      .filter((entity) => entity.Status === status)
      .map((entity) => this.deserialize(entity));
  }

  /**
   * Returns the current (latest) record for every tenant in the registry.
   *
   * Iterates the registry table and resolves each entry to its current version.
   * Entries where the current version record is missing are silently skipped.
   *
   * @returns An array of the most recent {@link TenantRecord} for every tenant.
   */
  async listAllCurrent(): Promise<TenantRecord[]> {
    const registryTable = await this.registryTable();
    const results: TenantRecord[] = [];

    if (registryTable) {
      for await (const registry of registryTable.listEntities<Record<string, unknown>>()) {
        const tenant = await this.getVersion(
          String(registry.partitionKey),
          String(registry.CurrentVersion ?? 'v1'),
        );
        if (tenant) {
          results.push(tenant);
        }
      }
      return results;
    }

    for (const registry of Object.values(this.memory[REGISTRY_TABLE])) {
      const tenant = await this.getVersion(
        String(registry.partitionKey),
        String(registry.CurrentVersion ?? 'v1'),
      );
      if (tenant) {
        results.push(tenant);
      }
    }

    return results;
  }

  /**
   * Determines the next version string for a tenant by incrementing the highest existing version.
   *
   * Returns `'v1'` when no previous versions exist.
   *
   * @param tenantName - The tenant partition key to look up existing versions for.
   * @returns The next version string (e.g. `'v4'` if the current max is `v3`).
   */
  private async nextVersion(tenantName: string): Promise<string> {
    const versions = await this.listVersions(tenantName);
    if (versions.length === 0) {
      return 'v1';
    }

    const maxNumber = Math.max(
      ...versions.map((version) => Number.parseInt(version.RowKey.replace(/^v/, ''), 10)),
    );
    return `v${maxNumber + 1}`;
  }

  /**
   * Creates or replaces the registry entry that maps a tenant name to its current version.
   *
   * @param tenantName - The unique tenant identifier used as the partition key.
   * @param version - The version string to record as the current version (e.g. `'v2'`).
   */
  private async upsertRegistry(tenantName: string, version: string): Promise<void> {
    const now = new Date().toISOString();
    const entity = {
      partitionKey: tenantName,
      rowKey: 'current',
      CurrentVersion: version,
      Status: 'active',
      CreatedAt: now,
    };

    const table = await this.registryTable();
    if (table) {
      await table.upsertEntity(entity, 'Replace');
      return;
    }

    this.memory[REGISTRY_TABLE][tenantName] = entity;
  }

  /**
   * Reads the registry entry for a tenant, returning the raw entity or `null` if absent.
   *
   * @param tenantName - The unique tenant identifier to look up.
   * @returns The raw registry entity, or `null` if not found.
   */
  private async getRegistry(tenantName: string): Promise<Record<string, unknown> | null> {
    const table = await this.registryTable();
    if (table) {
      try {
        return await table.getEntity<Record<string, unknown>>(tenantName, 'current');
      } catch {
        return null;
      }
    }

    return this.memory[REGISTRY_TABLE][tenantName] ?? null;
  }

  /**
   * Deserializes a raw storage entity into a typed {@link TenantRecord}.
   *
   * Normalizes `partitionKey`/`rowKey` aliases and JSON-parses the `FormData` and
   * `GeneratedTfvars` fields. Invalid JSON in those fields is left as the raw string.
   *
   * @param entity - The raw key-value entity from the storage backend.
   * @returns The deserialized {@link TenantRecord}.
   */
  private deserialize(entity: Record<string, unknown>): TenantRecord {
    const result = {
      ...entity,
      PartitionKey: String(entity.partitionKey ?? entity.PartitionKey ?? ''),
      RowKey: String(entity.rowKey ?? entity.RowKey ?? ''),
    } as Record<string, unknown>;
    for (const field of ['FormData', 'GeneratedTfvars']) {
      if (typeof result[field] === 'string') {
        try {
          result[field] = JSON.parse(result[field] as string);
        } catch {
          // Preserve raw string when parsing fails.
        }
      }
    }

    return result as unknown as TenantRecord;
  }

  /**
   * Resolves the requests {@link TableClient} after ensuring the Azure tables exist.
   *
   * Returns `null` when no Table Storage client is configured, indicating in-memory mode.
   *
   * @returns The initialized requests {@link TableClient}, or `null` for in-memory mode.
   */
  private async requestsTable(): Promise<TableClient | null> {
    if (!this.requestsTableClient) {
      return null;
    }

    await this.ensureTables();
    return this.requestsTableClient;
  }

  /**
   * Resolves the registry {@link TableClient} after ensuring the Azure tables exist.
   *
   * Returns `null` when no Table Storage client is configured, indicating in-memory mode.
   *
   * @returns The initialized registry {@link TableClient}, or `null` for in-memory mode.
   */
  private async registryTable(): Promise<TableClient | null> {
    if (!this.registryTableClient) {
      return null;
    }

    await this.ensureTables();
    return this.registryTableClient;
  }

  /**
   * Ensures both the `TenantRequests` and `TenantRegistry` Azure Tables exist.
   *
   * The combined creation promise is cached so that concurrent callers share a single
   * creation attempt rather than issuing redundant requests.
   */
  private async ensureTables(): Promise<void> {
    if (!this.requestsTableClient || !this.registryTableClient) {
      return;
    }

    if (!this.ensureTablesPromise) {
      this.ensureTablesPromise = (async () => {
        await this.requestsTableClient!.createTable().catch((error: unknown) => {
          this.logger.error(
            `Failed to ensure Azure Table ${REQUESTS_TABLE}`,
            error instanceof Error ? error.stack : String(error),
          );
          this.ensureTablesPromise = null;
          throw error;
        });
        await this.registryTableClient!.createTable().catch((error: unknown) => {
          this.logger.error(
            `Failed to ensure Azure Table ${REGISTRY_TABLE}`,
            error instanceof Error ? error.stack : String(error),
          );
          this.ensureTablesPromise = null;
          throw error;
        });
      })();
    }

    await this.ensureTablesPromise;
  }
}
