import { Injectable, Logger } from '@nestjs/common';
import { TableClient, TableEntity } from '@azure/data-tables';
import { DefaultAzureCredential } from '@azure/identity';

import { getSettings } from '../config/settings';
import type { PortalLoginState, PortalRedirectState, PortalSessionRecord } from '../types';

const SESSIONS_TABLE = 'TenantPortalSessions';
const LOGIN_PARTITION = 'login';
const REDIRECT_PARTITION = 'redirect';
const SESSION_PARTITION = 'session';

type MemorySessionEntities = Record<string, Record<string, unknown>>;

const IN_MEMORY_SESSION_ENTITIES: MemorySessionEntities = {};

@Injectable()
export class SessionStoreService {
  private readonly logger = new Logger(SessionStoreService.name);
  private readonly tableClient: TableClient | null;
  private readonly memory: MemorySessionEntities;
  private ensureTablePromise: Promise<void> | null = null;

  /**
   * Reads connection settings and initialises either an Azure Table Storage client
   * or an in-memory fallback when no storage credentials are configured.
   */
  constructor() {
    const settings = getSettings();
    if (settings.tableStorageConnectionString) {
      this.logger.log(`Using Azure Table Storage connection string for ${SESSIONS_TABLE}`);
      this.tableClient = TableClient.fromConnectionString(
        settings.tableStorageConnectionString,
        SESSIONS_TABLE,
      );
    } else if (settings.tableStorageAccountUrl) {
      this.logger.log(
        `Using Azure AD credential for ${SESSIONS_TABLE} via ${settings.tableStorageAccountUrl}`,
      );
      this.tableClient = new TableClient(
        settings.tableStorageAccountUrl,
        SESSIONS_TABLE,
        new DefaultAzureCredential(),
      );
    } else {
      this.logger.warn(
        `No Azure Table Storage configuration found for ${SESSIONS_TABLE}; falling back to in-memory storage`,
      );
      this.tableClient = null;
    }

    this.memory = IN_MEMORY_SESSION_ENTITIES;
  }

  /**
   * Clears all in-memory session and login-state records.
   *
   * Intended for use in tests to restore a clean state between test runs.
   */
  static resetInMemoryStore(): void {
    for (const key of Object.keys(IN_MEMORY_SESSION_ENTITIES)) {
      delete IN_MEMORY_SESSION_ENTITIES[key];
    }
  }

  /**
   * Persists a login-state record so it can be retrieved by its `state` token during the
   * OIDC callback.
   *
   * @param state - The login-state object containing the PKCE code verifier and redirect metadata.
   */
  async saveLoginState(state: PortalLoginState): Promise<void> {
    await this.upsertEntity(LOGIN_PARTITION, state.state, {
      CodeVerifier: state.codeVerifier,
      RedirectUri: state.redirectUri,
      ReturnTo: state.returnTo,
      CreatedAt: state.createdAt,
      ExpiresAt: state.expiresAt,
    });
  }

  /**
   * Retrieves and atomically deletes the login-state record for the given `state` token.
   *
   * Returns `null` if the state is not found or has already expired.
   *
   * @param state - The `state` token received in the OIDC authorization callback.
   * @returns The matching {@link PortalLoginState}, or `null` if absent or expired.
   */
  async consumeLoginState(state: string): Promise<PortalLoginState | null> {
    const entity = await this.getEntity(LOGIN_PARTITION, state);
    await this.deleteEntity(LOGIN_PARTITION, state);
    if (!entity) {
      return null;
    }

    const loginState = this.deserializeLoginState(state, entity);
    if (Date.parse(loginState.expiresAt) <= Date.now()) {
      return null;
    }

    return loginState;
  }

  /**
   * Persists a short-lived redirect-state record for internal post-auth redirects.
   *
   * @param state - The redirect-state object containing the validated target path.
   */
  async saveRedirectState(state: PortalRedirectState): Promise<void> {
    await this.upsertEntity(REDIRECT_PARTITION, state.state, {
      ReturnTo: state.returnTo,
      CreatedAt: state.createdAt,
      ExpiresAt: state.expiresAt,
    });
  }

  /**
   * Retrieves and atomically deletes the redirect-state record for the given state token.
   *
   * Returns `null` if the state is not found or has already expired.
   *
   * @param state - The redirect state token received from the internal callback route.
   * @returns The matching {@link PortalRedirectState}, or `null` if absent or expired.
   */
  async consumeRedirectState(state: string): Promise<PortalRedirectState | null> {
    const entity = await this.getEntity(REDIRECT_PARTITION, state);
    await this.deleteEntity(REDIRECT_PARTITION, state);
    if (!entity) {
      return null;
    }

    const redirectState = this.deserializeRedirectState(state, entity);
    if (Date.parse(redirectState.expiresAt) <= Date.now()) {
      return null;
    }

    return redirectState;
  }

  /**
   * Persists a session record, creating or replacing any existing record with the same ID.
   *
   * @param session - The session record to save, including user info and token data.
   */
  async saveSession(session: PortalSessionRecord): Promise<void> {
    await this.upsertEntity(SESSION_PARTITION, session.id, {
      User: JSON.stringify(session.user),
      AccessToken: session.accessToken,
      RefreshToken: session.refreshToken,
      IdToken: session.idToken,
      TokenType: session.tokenType,
      CreatedAt: session.createdAt,
      UpdatedAt: session.updatedAt,
      ExpiresAt: session.expiresAt,
    });
  }

  /**
   * Retrieves a session record by its ID, returning `null` if it does not exist or has expired.
   *
   * Expired sessions are deleted before returning `null`.
   *
   * @param sessionId - The unique session identifier.
   * @returns The active {@link PortalSessionRecord}, or `null` if absent or expired.
   */
  async getSession(sessionId: string): Promise<PortalSessionRecord | null> {
    const entity = await this.getEntity(SESSION_PARTITION, sessionId);
    if (!entity) {
      return null;
    }

    const session = this.deserializeSession(sessionId, entity);
    if (Date.parse(session.expiresAt) <= Date.now()) {
      await this.deleteSession(sessionId);
      return null;
    }

    return session;
  }

  /**
   * Deletes a session record by its ID.
   *
   * @param sessionId - The unique session identifier to remove.
   */
  async deleteSession(sessionId: string): Promise<void> {
    await this.deleteEntity(SESSION_PARTITION, sessionId);
  }

  /**
   * Deserializes a raw storage entity into a {@link PortalLoginState} object.
   *
   * @param state - The `state` token used as the row key.
   * @param entity - The raw key-value entity from the storage backend.
   * @returns The deserialized login state.
   */
  private deserializeLoginState(state: string, entity: Record<string, unknown>): PortalLoginState {
    return {
      state,
      codeVerifier: String(entity.CodeVerifier ?? ''),
      redirectUri: String(entity.RedirectUri ?? ''),
      returnTo: String(entity.ReturnTo ?? '/'),
      createdAt: String(entity.CreatedAt ?? new Date().toISOString()),
      expiresAt: String(entity.ExpiresAt ?? new Date(0).toISOString()),
    };
  }

  /**
   * Deserializes a raw storage entity into a {@link PortalRedirectState} object.
   *
   * @param state - The redirect-state token used as the row key.
   * @param entity - The raw key-value entity from the storage backend.
   * @returns The deserialized redirect state.
   */
  private deserializeRedirectState(
    state: string,
    entity: Record<string, unknown>,
  ): PortalRedirectState {
    return {
      state,
      returnTo: String(entity.ReturnTo ?? '/'),
      createdAt: String(entity.CreatedAt ?? new Date().toISOString()),
      expiresAt: String(entity.ExpiresAt ?? new Date(0).toISOString()),
    };
  }

  /**
   * Deserializes a raw storage entity into a {@link PortalSessionRecord} object.
   *
   * The `User` field is stored as a JSON string and parsed back into a structured object.
   * An invalid JSON value results in an empty user placeholder rather than an error.
   *
   * @param sessionId - The session ID used as the row key.
   * @param entity - The raw key-value entity from the storage backend.
   * @returns The deserialized session record.
   */
  private deserializeSession(
    sessionId: string,
    entity: Record<string, unknown>,
  ): PortalSessionRecord {
    const rawUser = typeof entity.User === 'string' ? entity.User : '{}';
    let user: PortalSessionRecord['user'] = {
      email: '',
      name: '',
      preferred_username: '',
      roles: [],
    };

    try {
      user = JSON.parse(rawUser) as PortalSessionRecord['user'];
    } catch {
      // Preserve default empty user when stored JSON is invalid.
    }

    return {
      id: sessionId,
      user,
      accessToken: String(entity.AccessToken ?? ''),
      refreshToken: String(entity.RefreshToken ?? ''),
      idToken: String(entity.IdToken ?? ''),
      tokenType: String(entity.TokenType ?? 'Bearer'),
      createdAt: String(entity.CreatedAt ?? new Date().toISOString()),
      updatedAt: String(entity.UpdatedAt ?? new Date().toISOString()),
      expiresAt: String(entity.ExpiresAt ?? new Date(0).toISOString()),
    };
  }

  /**
   * Upserts an entity into the storage backend using the given partition and row key.
   *
   * Writes to Azure Table Storage when a client is available, otherwise writes to the
   * in-memory map. Errors from Table Storage are logged and re-thrown.
   *
   * @param partitionKey - The partition key for the entity.
   * @param rowKey - The row key uniquely identifying the entity within the partition.
   * @param values - The property bag to store alongside the keys.
   */
  private async upsertEntity(
    partitionKey: string,
    rowKey: string,
    values: Record<string, unknown>,
  ): Promise<void> {
    const entity = {
      partitionKey,
      rowKey,
      ...values,
    };

    const table = await this.table();
    if (table) {
      try {
        await table.upsertEntity(entity as TableEntity<Record<string, unknown>>, 'Replace');
      } catch (error) {
        this.logger.error(
          `Failed to upsert ${SESSIONS_TABLE} entity ${partitionKey}:${rowKey}`,
          error instanceof Error ? error.stack : String(error),
        );
        throw error;
      }
      return;
    }

    this.memory[`${partitionKey}:${rowKey}`] = entity;
  }

  /**
   * Reads a single entity from the storage backend by its partition and row key.
   *
   * Returns `null` when the entity does not exist or a Table Storage read error occurs.
   *
   * @param partitionKey - The partition key for the entity.
   * @param rowKey - The row key identifying the entity.
   * @returns The entity as a plain object, or `null` if not found.
   */
  private async getEntity(
    partitionKey: string,
    rowKey: string,
  ): Promise<Record<string, unknown> | null> {
    const table = await this.table();
    if (table) {
      try {
        return await table.getEntity<Record<string, unknown>>(partitionKey, rowKey);
      } catch (error) {
        this.logger.warn(
          `Failed to read ${SESSIONS_TABLE} entity ${partitionKey}:${rowKey}: ${error instanceof Error ? error.message : String(error)}`,
        );
        return null;
      }
    }

    return this.memory[`${partitionKey}:${rowKey}`] ?? null;
  }

  /**
   * Removes an entity from the storage backend by its partition and row key.
   *
   * Table Storage delete failures are logged as warnings but do not throw.
   *
   * @param partitionKey - The partition key for the entity.
   * @param rowKey - The row key identifying the entity to delete.
   */
  private async deleteEntity(partitionKey: string, rowKey: string): Promise<void> {
    const table = await this.table();
    if (table) {
      await table.deleteEntity(partitionKey, rowKey).catch((error: unknown) => {
        this.logger.warn(
          `Failed to delete ${SESSIONS_TABLE} entity ${partitionKey}:${rowKey}: ${error instanceof Error ? error.message : String(error)}`,
        );
      });
      return;
    }

    delete this.memory[`${partitionKey}:${rowKey}`];
  }

  /**
   * Resolves the {@link TableClient} after ensuring the Azure table exists.
   *
   * Returns `null` when no Table Storage client is configured, indicating that
   * the in-memory backend should be used instead.
   *
   * @returns The initialized {@link TableClient}, or `null` for in-memory mode.
   */
  private async table(): Promise<TableClient | null> {
    if (!this.tableClient) {
      return null;
    }

    await this.ensureTable();
    return this.tableClient;
  }

  /**
   * Ensures the `TenantPortalSessions` Azure Table exists, creating it if necessary.
   *
   * The table-creation promise is cached so that concurrent callers share a single
   * creation attempt rather than issuing redundant requests.
   */
  private async ensureTable(): Promise<void> {
    if (!this.tableClient) {
      return;
    }

    if (!this.ensureTablePromise) {
      this.ensureTablePromise = this.tableClient.createTable().catch((error: unknown) => {
        this.logger.error(
          `Failed to ensure Azure Table ${SESSIONS_TABLE}`,
          error instanceof Error ? error.stack : String(error),
        );
        this.ensureTablePromise = null;
        throw error;
      });
    }

    await this.ensureTablePromise;
  }
}
