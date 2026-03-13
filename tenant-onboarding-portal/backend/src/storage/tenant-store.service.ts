import { Injectable, Logger } from '@nestjs/common';
import { TableClient, TableEntity } from '@azure/data-tables';
import { DefaultAzureCredential } from '@azure/identity';

import { getSettings } from '../config/settings';
import type { TenantFormData, TenantRecord } from '../types';

const REQUESTS_TABLE = 'TenantRequests';
const REGISTRY_TABLE = 'TenantRegistry';
const USER_INDEX_TABLE = 'TenantUserIndex';
const STATUS_INDEX_TABLE = 'TenantStatusIndex';
const ACCESS_INDEX_TABLE = 'TenantAccessIndex';

type MemoryTables = Record<string, Record<string, Record<string, unknown>>>;

const IN_MEMORY_TABLES: MemoryTables = {
  [REQUESTS_TABLE]: {},
  [REGISTRY_TABLE]: {},
  [USER_INDEX_TABLE]: {},
  [STATUS_INDEX_TABLE]: {},
  [ACCESS_INDEX_TABLE]: {},
};

@Injectable()
export class TenantStoreService {
  private readonly logger = new Logger(TenantStoreService.name);
  private readonly requestsTableClient: TableClient | null;
  private readonly registryTableClient: TableClient | null;
  private readonly userIndexTableClient: TableClient | null;
  private readonly statusIndexTableClient: TableClient | null;
  private readonly accessIndexTableClient: TableClient | null;
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
        `Using Azure Table Storage connection string for ${REQUESTS_TABLE}, ${REGISTRY_TABLE}, and ${USER_INDEX_TABLE}`,
      );
      this.requestsTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        REQUESTS_TABLE,
      );
      this.registryTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        REGISTRY_TABLE,
      );
      this.userIndexTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        USER_INDEX_TABLE,
      );
      this.statusIndexTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        STATUS_INDEX_TABLE,
      );
      this.accessIndexTableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        ACCESS_INDEX_TABLE,
      );
    } else if (settings.tableStorageAccountUrl) {
      this.logger.log(
        `Using Azure AD credential for ${REQUESTS_TABLE}, ${REGISTRY_TABLE}, and ${USER_INDEX_TABLE} via ${settings.tableStorageAccountUrl}`,
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
      this.userIndexTableClient = new TableClient(
        settings.tableStorageAccountUrl,
        USER_INDEX_TABLE,
        credential,
      );
      this.statusIndexTableClient = new TableClient(
        settings.tableStorageAccountUrl,
        STATUS_INDEX_TABLE,
        credential,
      );
      this.accessIndexTableClient = new TableClient(
        settings.tableStorageAccountUrl,
        ACCESS_INDEX_TABLE,
        credential,
      );
    } else {
      this.logger.warn(
        `No Azure Table Storage configuration found for ${REQUESTS_TABLE}, ${REGISTRY_TABLE}, and ${USER_INDEX_TABLE}; falling back to in-memory storage`,
      );
      this.requestsTableClient = null;
      this.registryTableClient = null;
      this.userIndexTableClient = null;
      this.statusIndexTableClient = null;
      this.accessIndexTableClient = null;
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
    IN_MEMORY_TABLES[USER_INDEX_TABLE] = {};
    IN_MEMORY_TABLES[STATUS_INDEX_TABLE] = {};
    IN_MEMORY_TABLES[ACCESS_INDEX_TABLE] = {};
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
    const oldCurrent = await this.getCurrent(tenantName);
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
    try {
      await this.upsertUserIndex(submittedBy, tenantName, nextVersion);
    } catch (error) {
      this.logger.error(
        `Failed to upsert ${USER_INDEX_TABLE} entry for ${submittedBy} → ${tenantName}:${nextVersion}; index may be stale`,
        error instanceof Error ? error.stack : String(error),
      );
    }
    try {
      await this.upsertStatusIndex('submitted', tenantName, nextVersion);
    } catch (error) {
      this.logger.error(
        `Failed to upsert ${STATUS_INDEX_TABLE} entry for ${tenantName}:${nextVersion}; index may be stale`,
        error instanceof Error ? error.stack : String(error),
      );
    }
    try {
      await this.rebuildAccessIndex(tenantName, submittedBy, formData, oldCurrent);
    } catch (error) {
      this.logger.error(
        `Failed to rebuild ${ACCESS_INDEX_TABLE} for ${tenantName}; index may be stale`,
        error instanceof Error ? error.stack : String(error),
      );
    }
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
    let oldStatus: string | undefined;
    const table = await this.requestsTable();
    if (table) {
      try {
        const entity = await table.getEntity<Record<string, unknown>>(tenantName, version);
        oldStatus = typeof entity.Status === 'string' ? entity.Status : undefined;
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
    } else {
      const key = `${tenantName}:${version}`;
      const entity = this.memory[REQUESTS_TABLE][key];
      if (entity) {
        oldStatus = typeof entity.Status === 'string' ? entity.Status : undefined;
        entity.Status = status;
        entity.ReviewedBy = reviewedBy;
        entity.ReviewNotes = reviewNotes;
        entity.UpdatedAt = now;
      }
    }

    if (oldStatus && oldStatus !== status) {
      try {
        await this.deleteStatusIndex(oldStatus, tenantName, version);
        await this.upsertStatusIndex(status, tenantName, version);
      } catch (error) {
        this.logger.error(
          `Failed to move ${STATUS_INDEX_TABLE} entry ${tenantName}:${version} from ${oldStatus} → ${status}; index may be stale`,
          error instanceof Error ? error.stack : String(error),
        );
      }
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
   * Uses `TenantUserIndex` (partitionKey = lowercase email) to avoid a full
   * table scan on `TenantRequests`, then resolves each entry with a point-read.
   * The comparison is case-insensitive. Results are not sorted.
   *
   * @param email - The submitter's email address to filter by.
   * @returns An array of {@link TenantRecord} objects submitted by that user.
   */
  async listByUser(email: string): Promise<TenantRecord[]> {
    const emailLower = email.toLowerCase();
    const safeEmail = emailLower.replace(/'/g, "''");
    const indexTable = await this.userIndexTable();

    if (indexTable) {
      const records: TenantRecord[] = [];
      for await (const entry of indexTable.listEntities<Record<string, unknown>>({
        queryOptions: { filter: `PartitionKey eq '${safeEmail}'` },
      })) {
        const record = await this.getVersion(String(entry.TenantName), String(entry.Version));
        if (record) {
          records.push(record);
        }
      }
      return records;
    }

    const indexEntries = Object.values(this.memory[USER_INDEX_TABLE]).filter(
      (entry) => String(entry.partitionKey) === emailLower,
    );
    const records: TenantRecord[] = [];
    for (const entry of indexEntries) {
      const record = await this.getVersion(String(entry.TenantName), String(entry.Version));
      if (record) {
        records.push(record);
      }
    }
    return records;
  }

  /**
   * Returns all current tenant records accessible to a given user — either submitted
   * by them or where they appear in the `admin_users` list.
   *
   * Uses `TenantAccessIndex` (partitionKey = lowercase email) to avoid loading all
   * tenants. The index is rebuilt each time a request is created.
   *
   * @param email - The user's email address.
   * @returns An array of accessible {@link TenantRecord} objects.
   */
  async listAccessibleByUser(email: string): Promise<TenantRecord[]> {
    const emailLower = email.toLowerCase();
    const safeEmail = emailLower.replace(/'/g, "''");
    const accessTable = await this.accessIndexTable();

    if (accessTable) {
      const records: TenantRecord[] = [];
      for await (const entry of accessTable.listEntities<Record<string, unknown>>({
        queryOptions: { filter: `PartitionKey eq '${safeEmail}'` },
      })) {
        const record = await this.getCurrent(String(entry.TenantName));
        if (record) {
          records.push(record);
        }
      }
      return records;
    }

    const indexEntries = Object.values(this.memory[ACCESS_INDEX_TABLE]).filter(
      (entry) => String(entry.partitionKey) === emailLower,
    );
    const records: TenantRecord[] = [];
    for (const entry of indexEntries) {
      const record = await this.getCurrent(String(entry.TenantName));
      if (record) {
        records.push(record);
      }
    }
    return records;
  }

  /**
   * Returns all tenant requests that match the given status value.
   *
   * Uses `TenantStatusIndex` (partitionKey = status) to avoid a cross-partition
   * scan on `TenantRequests`. The index is maintained by `createRequest` and
   * `updateStatus`.
   *
   * @param status - The status to filter by (e.g. `'submitted'`, `'approved'`).
   * @returns An array of {@link TenantRecord} objects with the matching status.
   */
  async listByStatus(status: string): Promise<TenantRecord[]> {
    const safeStatus = status.replace(/'/g, "''");
    const indexTable = await this.statusIndexTable();

    if (indexTable) {
      const records: TenantRecord[] = [];
      for await (const entry of indexTable.listEntities<Record<string, unknown>>({
        queryOptions: { filter: `PartitionKey eq '${safeStatus}'` },
      })) {
        const record = await this.getVersion(String(entry.TenantName), String(entry.Version));
        if (record) {
          records.push(record);
        }
      }
      return records;
    }

    const indexEntries = Object.values(this.memory[STATUS_INDEX_TABLE]).filter(
      (entry) => String(entry.partitionKey) === status,
    );
    const records: TenantRecord[] = [];
    for (const entry of indexEntries) {
      const record = await this.getVersion(String(entry.TenantName), String(entry.Version));
      if (record) {
        records.push(record);
      }
    }
    return records;
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
   * Writes an entry to `TenantUserIndex` so that `listByUser` can find the request
   * by querying the email partition key instead of scanning `TenantRequests`.
   *
   * @param email - The submitter's email address (stored lowercased as the partition key).
   * @param tenantName - The unique tenant identifier.
   * @param version - The request version to index (e.g. `'v1'`).
   */
  private async upsertUserIndex(email: string, tenantName: string, version: string): Promise<void> {
    const entity = {
      partitionKey: email.toLowerCase(),
      rowKey: `${tenantName}:${version}`,
      TenantName: tenantName,
      Version: version,
    };

    const table = await this.userIndexTable();
    if (table) {
      await table.upsertEntity(entity, 'Replace');
      return;
    }

    this.memory[USER_INDEX_TABLE][`${email.toLowerCase()}:${tenantName}:${version}`] = entity;
  }

  /**
   * Writes an entry to `TenantStatusIndex` so that `listByStatus` can use a
   * single-partition query instead of scanning `TenantRequests`.
   *
   * @param status - The status value used as the partition key.
   * @param tenantName - The unique tenant identifier.
   * @param version - The request version (e.g. `'v1'`).
   */
  private async upsertStatusIndex(
    status: string,
    tenantName: string,
    version: string,
  ): Promise<void> {
    const entity = {
      partitionKey: status,
      rowKey: `${tenantName}:${version}`,
      TenantName: tenantName,
      Version: version,
    };

    const table = await this.statusIndexTable();
    if (table) {
      await table.upsertEntity(entity, 'Replace');
      return;
    }

    this.memory[STATUS_INDEX_TABLE][`${status}:${tenantName}:${version}`] = entity;
  }

  /**
   * Removes an entry from `TenantStatusIndex` — called when a request's status changes.
   *
   * @param status - The old status value (partition key to delete from).
   * @param tenantName - The unique tenant identifier.
   * @param version - The request version (e.g. `'v1'`).
   */
  private async deleteStatusIndex(
    status: string,
    tenantName: string,
    version: string,
  ): Promise<void> {
    const table = await this.statusIndexTable();
    if (table) {
      try {
        await table.deleteEntity(status, `${tenantName}:${version}`);
      } catch {
        // Entity may not exist; safe to ignore.
      }
      return;
    }

    delete this.memory[STATUS_INDEX_TABLE][`${status}:${tenantName}:${version}`];
  }

  /**
   * Writes an entry to `TenantAccessIndex` so that `listAccessibleByUser` can use
   * a single-partition query instead of loading all current tenants.
   *
   * @param email - The user's email address (stored lowercased as the partition key).
   * @param tenantName - The unique tenant identifier used as the row key.
   */
  private async upsertAccessIndex(email: string, tenantName: string): Promise<void> {
    const entity = {
      partitionKey: email.toLowerCase(),
      rowKey: tenantName,
      TenantName: tenantName,
    };

    const table = await this.accessIndexTable();
    if (table) {
      await table.upsertEntity(entity, 'Replace');
      return;
    }

    this.memory[ACCESS_INDEX_TABLE][`${email.toLowerCase()}:${tenantName}`] = entity;
  }

  /**
   * Removes an entry from `TenantAccessIndex` — called when a user loses access to a tenant.
   *
   * @param email - The user's email address.
   * @param tenantName - The unique tenant identifier.
   */
  private async deleteAccessIndex(email: string, tenantName: string): Promise<void> {
    const table = await this.accessIndexTable();
    if (table) {
      try {
        await table.deleteEntity(email.toLowerCase(), tenantName);
      } catch {
        // Entity may not exist; safe to ignore.
      }
      return;
    }

    delete this.memory[ACCESS_INDEX_TABLE][`${email.toLowerCase()}:${tenantName}`];
  }

  /**
   * Rebuilds `TenantAccessIndex` entries for a tenant after a new version is created.
   * Removes stale entries for users who lost access and upserts entries for current users.
   *
   * @param tenantName - The unique tenant identifier.
   * @param submittedBy - The email of the user who submitted the new version.
   * @param formData - The raw form data containing `admin_users`.
   * @param oldCurrent - The previous current record, or `null` for new tenants.
   */
  private async rebuildAccessIndex(
    tenantName: string,
    submittedBy: string,
    formData: Record<string, unknown>,
    oldCurrent: TenantRecord | null,
  ): Promise<void> {
    const oldEmails = new Set<string>();
    if (oldCurrent) {
      oldEmails.add(oldCurrent.SubmittedBy.toLowerCase());
      const oldFormData = oldCurrent.FormData as TenantFormData | undefined;
      for (const email of oldFormData?.admin_users ?? []) {
        oldEmails.add(email.toLowerCase());
      }
    }

    const newEmails = new Set<string>();
    newEmails.add(submittedBy.toLowerCase());
    const newAdmins = Array.isArray(formData.admin_users) ? (formData.admin_users as string[]) : [];
    for (const email of newAdmins) {
      newEmails.add(email.toLowerCase());
    }

    for (const email of oldEmails) {
      if (!newEmails.has(email)) {
        await this.deleteAccessIndex(email, tenantName);
      }
    }

    for (const email of newEmails) {
      await this.upsertAccessIndex(email, tenantName);
    }
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
   * Resolves the user-index {@link TableClient} after ensuring the Azure tables exist.
   *
   * Returns `null` when no Table Storage client is configured, indicating in-memory mode.
   *
   * @returns The initialized user-index {@link TableClient}, or `null` for in-memory mode.
   */
  private async userIndexTable(): Promise<TableClient | null> {
    if (!this.userIndexTableClient) {
      return null;
    }

    await this.ensureTables();
    return this.userIndexTableClient;
  }

  /**
   * Resolves the status-index {@link TableClient} after ensuring the Azure tables exist.
   *
   * @returns The initialized status-index {@link TableClient}, or `null` for in-memory mode.
   */
  private async statusIndexTable(): Promise<TableClient | null> {
    if (!this.statusIndexTableClient) {
      return null;
    }

    await this.ensureTables();
    return this.statusIndexTableClient;
  }

  /**
   * Resolves the access-index {@link TableClient} after ensuring the Azure tables exist.
   *
   * @returns The initialized access-index {@link TableClient}, or `null` for in-memory mode.
   */
  private async accessIndexTable(): Promise<TableClient | null> {
    if (!this.accessIndexTableClient) {
      return null;
    }

    await this.ensureTables();
    return this.accessIndexTableClient;
  }

  /**
   * Ensures all portal Azure Tables exist. Tables are provisioned by Terraform;
   * this method is a no-op placeholder kept so callers can await table readiness
   * without code changes if a self-provisioning path is ever needed.
   *
   * The promise is cached so concurrent callers share a single check.
   */
  private async ensureTables(): Promise<void> {
    if (
      !this.requestsTableClient ||
      !this.registryTableClient ||
      !this.userIndexTableClient ||
      !this.statusIndexTableClient ||
      !this.accessIndexTableClient
    ) {
      return;
    }

    // Tables are managed by Terraform — no createTable() calls needed.
    this.ensureTablesPromise ??= Promise.resolve();
    await this.ensureTablesPromise;
  }
}
