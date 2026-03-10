import { UnprocessableEntityException } from '@nestjs/common';

import { FORM_SCHEMA } from './form-schema';
import type { TenantFormData } from '../types';

const DEFAULTS = FORM_SCHEMA.defaults;
const VALIDATION = FORM_SCHEMA.validation;
const PROJECT_NAME_REGEX = VALIDATION.project_name.pattern
  ? new RegExp(VALIDATION.project_name.pattern)
  : null;
const PROJECT_NAME_MAX_LENGTH = 30;

/**
 * Asserts that a value is a plain, non-array JSON object.
 *
 * @param value - The unknown value to inspect.
 * @returns The value cast to `Record<string, unknown>`.
 * @throws UnprocessableEntityException when the value is not a plain object.
 */
function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new UnprocessableEntityException('Request body must be a JSON object');
  }

  return value as Record<string, unknown>;
}

/**
 * Casts a value to a string, returning a fallback when the value is not already a string.
 *
 * @param value - The unknown value to cast.
 * @param fallback - The string to return when `value` is not a string. Defaults to `''`.
 * @returns The original string value or the fallback.
 */
function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

/**
 * Casts a value to a boolean, returning a fallback when the value is not already a boolean.
 *
 * @param value - The unknown value to cast.
 * @param fallback - The boolean to return when `value` is not a boolean.
 * @returns The original boolean value or the fallback.
 */
function asBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

/**
 * Casts a value to a finite number, returning a fallback when the value cannot
 * be interpreted as a number. Accepts numeric strings as well as number literals.
 *
 * @param value - The unknown value to cast.
 * @param fallback - The number to return when `value` cannot be parsed as a finite number.
 * @returns The parsed finite number or the fallback.
 */
function _asNumber(value: unknown, fallback: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return fallback;
}

/**
 * Casts a value to an array of strings. Arrays are filtered to string elements;
 * a string scalar is split on commas. All other values return the fallback.
 *
 * @param value - The unknown value to convert.
 * @param fallback - The array to return when `value` cannot be converted. Defaults to `[]`.
 * @returns An array of strings.
 */
function asStringArray(value: unknown, fallback: string[] = []): string[] {
  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === 'string');
  }

  if (typeof value === 'string') {
    return value
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return fallback;
}

/**
 * Validates and normalises a tenant project name. The name must be lowercase,
 * meet the minimum length, not exceed 30 characters, and match the configured regex.
 *
 * @param projectName - The raw project name value from the form.
 * @returns The normalised (trimmed, lowercased) project name.
 * @throws UnprocessableEntityException when the project name fails validation.
 */
function validateProjectName(projectName: string): string {
  const normalized = projectName.trim().toLowerCase();
  if (projectName !== normalized) {
    throw new UnprocessableEntityException(VALIDATION.project_name.message);
  }

  if (
    normalized.length < (VALIDATION.project_name.min_length ?? 0) ||
    normalized.length > PROJECT_NAME_MAX_LENGTH ||
    (PROJECT_NAME_REGEX && !PROJECT_NAME_REGEX.test(normalized))
  ) {
    throw new UnprocessableEntityException(VALIDATION.project_name.message);
  }

  return normalized;
}

/**
 * Trims a string and validates that it is non-empty after trimming.
 *
 * @param value - The raw string value to validate.
 * @param message - The error message to include in the exception when the value is blank.
 * @returns The trimmed non-empty string.
 * @throws UnprocessableEntityException when the trimmed value is empty.
 */
function validateRequiredString(value: string, message: string): string {
  const normalized = value.trim();
  if (!normalized) {
    throw new UnprocessableEntityException(message);
  }

  return normalized;
}

/**
 * Validates that a string value is included in the list of allowed values.
 *
 * @param value - The string to validate against the allowed list.
 * @param allowedValues - The permitted values, or undefined to skip the check.
 * @param message - The error message passed to the exception when the value is not allowed.
 * @returns The validated value unchanged.
 * @throws UnprocessableEntityException when the value is not in the allowed list.
 */
function validateAllowedValue(
  value: string,
  allowedValues: readonly string[] | undefined,
  message: string,
): string {
  if (!allowedValues?.includes(value)) {
    throw new UnprocessableEntityException(message);
  }

  return value;
}

/**
 * Trims, lowercases, and validates that each non-empty email in the list ends
 * with `@gov.bc.ca`.
 *
 * @param values - An array of raw email strings to validate.
 * @param fieldLabel - A human-readable field label used in exception messages.
 * @returns An array of normalised, validated email strings.
 * @throws UnprocessableEntityException when any email does not end with `@gov.bc.ca`.
 */
function validateGovEmails(values: string[], fieldLabel: string): string[] {
  return values
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean)
    .map((value) => {
      if (!value.endsWith(VALIDATION.admin_users.email_domain)) {
        throw new UnprocessableEntityException(`${fieldLabel} email must be @gov.bc.ca: ${value}`);
      }

      return value;
    });
}

/**
 * Parses and validates a raw tenant form submission, casting all fields from
 * unknown input types, applying default values from the form schema, and
 * throwing detailed validation errors for any invalid fields.
 *
 * @param input - The raw request body as received from the HTTP layer.
 * @returns A fully validated and typed `TenantFormData` object.
 * @throws UnprocessableEntityException for any field that fails validation.
 */
export function parseTenantForm(input: unknown): TenantFormData {
  const payload = asRecord(input);

  const openaiEnabled = asBoolean(payload.openai_enabled, DEFAULTS.openai_enabled);
  const documentIntelligenceEnabled = asBoolean(
    payload.document_intelligence_enabled,
    DEFAULTS.document_intelligence_enabled,
  );
  const legacyAdminEmails = asStringArray(payload.admin_emails);
  const adminUsers = asStringArray(payload.admin_users, legacyAdminEmails);

  if (!openaiEnabled && !documentIntelligenceEnabled) {
    throw new UnprocessableEntityException(VALIDATION.primary_services.message);
  }

  const modelFamilies = asStringArray(payload.model_families, DEFAULTS.model_families);
  const validModelFamilies = VALIDATION.model_families.allowed_values ?? [];
  if (modelFamilies.some((family) => !validModelFamilies.includes(family))) {
    throw new UnprocessableEntityException(VALIDATION.model_families.message);
  }
  if (
    openaiEnabled &&
    modelFamilies.length < (VALIDATION.model_families.min_items_when_openai_enabled ?? 0)
  ) {
    throw new UnprocessableEntityException(VALIDATION.model_families.message);
  }

  const ministry = validateAllowedValue(
    validateRequiredString(
      asString(payload.ministry, DEFAULTS.ministry),
      VALIDATION.ministry.message,
    ),
    VALIDATION.ministry.allowed_values,
    VALIDATION.ministry.message,
  );

  const capacityTier = validateAllowedValue(
    asString(payload.capacity_tier, DEFAULTS.capacity_tier),
    VALIDATION.capacity_tier.allowed_values,
    VALIDATION.capacity_tier.message,
  );

  return {
    project_name: validateProjectName(asString(payload.project_name)),
    display_name: validateRequiredString(
      asString(payload.display_name),
      VALIDATION.display_name.message,
    ),
    ministry,
    department: asString(payload.department),
    openai_enabled: openaiEnabled,
    ai_search_enabled: asBoolean(payload.ai_search_enabled, DEFAULTS.ai_search_enabled),
    document_intelligence_enabled: documentIntelligenceEnabled,
    speech_services_enabled: asBoolean(
      payload.speech_services_enabled,
      DEFAULTS.speech_services_enabled,
    ),
    cosmos_db_enabled: asBoolean(payload.cosmos_db_enabled, DEFAULTS.cosmos_db_enabled),
    storage_account_enabled: asBoolean(
      payload.storage_account_enabled,
      DEFAULTS.storage_account_enabled,
    ),
    key_vault_enabled: asBoolean(payload.key_vault_enabled, DEFAULTS.key_vault_enabled),
    model_families: modelFamilies,
    capacity_tier: capacityTier,
    pii_redaction_enabled: asBoolean(payload.pii_redaction_enabled, DEFAULTS.pii_redaction_enabled),
    logging_enabled:
      typeof payload.logging_enabled === 'boolean'
        ? payload.logging_enabled
        : asBoolean(payload.usage_logging_enabled, DEFAULTS.logging_enabled),
    custom_rai_filters_enabled: asBoolean(
      payload.custom_rai_filters_enabled,
      DEFAULTS.custom_rai_filters_enabled,
    ),
    admin_users: validateGovEmails(adminUsers, 'Admin user'),
    write_users: validateGovEmails(asStringArray(payload.write_users), 'Write user'),
    read_users: validateGovEmails(asStringArray(payload.read_users), 'Read user'),
    form_version: asString(payload.form_version, DEFAULTS.form_version),
  };
}
