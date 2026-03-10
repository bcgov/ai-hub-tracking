import type { FormSchema, TenantFormPayload } from '../types';

export type TenantFormState = TenantFormPayload;
export type FormValidationErrors = Partial<
  Record<keyof TenantFormPayload | 'services' | 'model_families', string>
>;

/**
 * Toggles a model family selection in the form state.
 * Removes the family if already selected, or appends it if not present.
 * @param family - The model family identifier to toggle.
 * @param form - Current form state.
 * @param setForm - State setter function for the form.
 */
export function toggleModelFamily(
  family: string,
  form: TenantFormState,
  setForm: (value: TenantFormState) => void,
) {
  if (form.model_families.includes(family)) {
    setForm({
      ...form,
      model_families: form.model_families.filter((item) => item !== family),
    });
    return;
  }
  setForm({ ...form, model_families: [...form.model_families, family] });
}

/**
 * Updates the email address at a specific index within a role's email list.
 * @param role - The role field to update (`admin_users`, `write_users`, or `read_users`).
 * @param index - Zero-based index of the email entry to replace.
 * @param value - New email address string.
 * @param form - Current form state.
 * @param setForm - State setter function for the form.
 */
export function updateRoleEmail(
  role: 'admin_users' | 'write_users' | 'read_users',
  index: number,
  value: string,
  form: TenantFormState,
  setForm: (value: TenantFormState) => void,
) {
  const nextEmails = [...form[role]];
  nextEmails[index] = value;
  setForm({ ...form, [role]: nextEmails });
}

/**
 * Removes the email entry at a specific index from a role's email list.
 * Ensures the list always has at least one entry by substituting an empty string when the last item is removed.
 * @param role - The role field to modify (`admin_users`, `write_users`, or `read_users`).
 * @param index - Zero-based index of the email entry to remove.
 * @param form - Current form state.
 * @param setForm - State setter function for the form.
 */
export function removeRoleEmail(
  role: 'admin_users' | 'write_users' | 'read_users',
  index: number,
  form: TenantFormState,
  setForm: (value: TenantFormState) => void,
) {
  const nextEmails = form[role].filter((_, currentIndex) => currentIndex !== index);
  setForm({ ...form, [role]: nextEmails.length > 0 ? nextEmails : [''] });
}

/**
 * Produces a clean `TenantFormPayload` by trimming string fields, filtering out invalid list values, and enforcing schema-allowed selections.
 * @param form - Raw form state to sanitize.
 * @param schema - Current form schema providing allowed values and defaults.
 * @returns Sanitized tenant form payload ready for submission.
 */
export function sanitizeForm(form: TenantFormState, schema: FormSchema): TenantFormPayload {
  return {
    ...form,
    project_name: form.project_name.trim(),
    display_name: form.display_name.trim(),
    ministry: form.ministry.trim(),
    department: form.department.trim(),
    capacity_tier: normalizeAllowedValue(
      form.capacity_tier,
      Object.keys(schema.capacity_tiers),
      schema.defaults.capacity_tier,
    ),
    model_families: form.model_families.filter((family) =>
      Object.prototype.hasOwnProperty.call(schema.model_families, family),
    ),
    admin_users: form.admin_users.map((email) => email.trim()).filter(Boolean),
    write_users: form.write_users.map((email) => email.trim()).filter(Boolean),
    read_users: form.read_users.map((email) => email.trim()).filter(Boolean),
    form_version: schema.version,
  };
}

/**
 * Normalizes an unknown value into a valid `TenantFormState`.
 * Applies schema defaults, remaps legacy fields, and filters out-of-range values.
 * @param value - Raw value from storage or an API response.
 * @param schema - Current form schema providing allowed values and defaults.
 * @returns Normalized form state safe to pass to form components.
 */
export function normalizeForm(value: unknown, schema: FormSchema): TenantFormState {
  if (!value || typeof value !== 'object') {
    return createFormFromSchema(schema.defaults, schema);
  }

  const source = value as Partial<TenantFormPayload> & {
    admin_emails?: string[];
    usage_logging_enabled?: boolean;
  };

  const defaults = createFormFromSchema(schema.defaults, schema);
  return {
    ...defaults,
    ...source,
    ministry: normalizeAllowedValue(source.ministry, schema.ministries, defaults.ministry),
    capacity_tier: normalizeAllowedValue(
      source.capacity_tier,
      Object.keys(schema.capacity_tiers),
      defaults.capacity_tier,
    ),
    logging_enabled:
      typeof source.logging_enabled === 'boolean'
        ? source.logging_enabled
        : typeof source.usage_logging_enabled === 'boolean'
          ? source.usage_logging_enabled
          : defaults.logging_enabled,
    model_families: Array.isArray(source.model_families)
      ? source.model_families.filter((family) =>
          Object.prototype.hasOwnProperty.call(schema.model_families, family),
        )
      : defaults.model_families,
    admin_users:
      Array.isArray(source.admin_users) && source.admin_users.length > 0
        ? source.admin_users
        : Array.isArray(source.admin_emails) && source.admin_emails.length > 0
          ? source.admin_emails
          : [''],
    write_users:
      Array.isArray(source.write_users) && source.write_users.length > 0
        ? source.write_users
        : [''],
    read_users:
      Array.isArray(source.read_users) && source.read_users.length > 0 ? source.read_users : [''],
    form_version: typeof source.form_version === 'string' ? source.form_version : schema.version,
  };
}

/**
 * Creates a `TenantFormState` from schema defaults, ensuring all list fields contain at least one entry.
 * @param defaults - Default values from the form schema.
 * @param schema - Current form schema providing allowed values.
 * @returns A fully initialized form state based on the provided defaults.
 */
function createFormFromSchema(
  defaults: FormSchema['defaults'],
  schema: FormSchema,
): TenantFormState {
  return {
    ...defaults,
    ministry: normalizeAllowedValue(
      defaults.ministry,
      schema.ministries,
      schema.ministries[0] ?? '',
    ),
    capacity_tier: normalizeAllowedValue(
      defaults.capacity_tier,
      Object.keys(schema.capacity_tiers),
      Object.keys(schema.capacity_tiers)[0] ?? '',
    ),
    model_families: defaults.model_families.filter((family) =>
      Object.prototype.hasOwnProperty.call(schema.model_families, family),
    ),
    admin_users: defaults.admin_users.length > 0 ? defaults.admin_users : [''],
    write_users: defaults.write_users.length > 0 ? defaults.write_users : [''],
    read_users: defaults.read_users.length > 0 ? defaults.read_users : [''],
    form_version: defaults.form_version ?? schema.version,
  };
}

/**
 * Returns the given value if it is present in the list of allowed values, otherwise returns the fallback.
 * @param value - The value to validate.
 * @param allowedValues - Array of permitted string values.
 * @param fallback - Value returned when `value` is absent or not in `allowedValues`.
 * @returns The validated value or the fallback.
 */
function normalizeAllowedValue(
  value: string | undefined,
  allowedValues: string[],
  fallback: string,
) {
  if (value && allowedValues.includes(value)) {
    return value;
  }

  return fallback;
}

/**
 * Validates a `TenantFormPayload` against the current form schema.
 * Returns a map of field-level error messages for any invalid fields.
 * @param form - The tenant form payload to validate.
 * @param schema - Form schema containing validation rules for each field.
 * @returns An object mapping field names to error message strings.
 */
export function validateTenantForm(
  form: TenantFormPayload,
  schema: FormSchema,
): FormValidationErrors {
  const errors: FormValidationErrors = {};
  const projectName = form.project_name.trim();
  const displayName = form.display_name.trim();

  if (!projectName) {
    errors.project_name = schema.validation.project_name.message;
  } else {
    const projectPattern = schema.validation.project_name.pattern
      ? new RegExp(schema.validation.project_name.pattern)
      : null;
    if (
      projectName !== projectName.toLowerCase() ||
      (schema.validation.project_name.min_length != null &&
        projectName.length < schema.validation.project_name.min_length) ||
      (projectPattern && !projectPattern.test(projectName))
    ) {
      errors.project_name = schema.validation.project_name.message;
    }
  }

  if (schema.validation.display_name.required && !displayName) {
    errors.display_name = schema.validation.display_name.message;
  }

  if (schema.validation.ministry.required && !schema.ministries.includes(form.ministry)) {
    errors.ministry = schema.validation.ministry.message;
  }

  const primaryServicesSelected = form.openai_enabled || form.document_intelligence_enabled;
  if (!primaryServicesSelected) {
    errors.services = schema.validation.primary_services.message;
  }

  if (form.openai_enabled) {
    if (
      form.model_families.length <
      (schema.validation.model_families.min_items_when_openai_enabled ?? 0)
    ) {
      errors.model_families = schema.validation.model_families.message;
    }
    if (!Object.prototype.hasOwnProperty.call(schema.capacity_tiers, form.capacity_tier)) {
      errors.capacity_tier = schema.validation.capacity_tier.message;
    }
  }

  for (const field of ['admin_users', 'write_users', 'read_users'] as const) {
    const validation = schema.validation[field];
    const emailPattern = validation.pattern ? new RegExp(validation.pattern, 'i') : null;
    const invalidEmail = form[field]
      .map((value) => value.trim())
      .filter(Boolean)
      .find((value) =>
        emailPattern
          ? !emailPattern.test(value)
          : validation.email_domain
            ? !value.toLowerCase().endsWith(validation.email_domain)
            : false,
      );

    if (invalidEmail) {
      errors[field] = validation.message;
    }
  }

  return errors;
}

/**
 * Returns `true` if any field in the validation error map contains a truthy error value.
 * @param errors - Validation error map produced by `validateTenantForm`.
 * @returns `true` when at least one validation error exists, otherwise `false`.
 */
export function hasValidationErrors(errors: FormValidationErrors) {
  return Object.values(errors).some(Boolean);
}
