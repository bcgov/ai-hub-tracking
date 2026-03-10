import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { Link, getRouteApi, useNavigate } from '@tanstack/react-router';

import { api } from '../api';
import { ProtectedRoute } from '../components/guards';
import { EmailListField, Field, InlineMessage, Panel, Toggle } from '../components/ui';
import type { FormSchema } from '../types';
import {
  type FormValidationErrors,
  type TenantFormState,
  hasValidationErrors,
  normalizeForm,
  removeRoleEmail,
  sanitizeForm,
  toggleModelFamily,
  updateRoleEmail,
  validateTenantForm,
} from '../utils/form-helpers';
import { getErrorMessage, getInputClassName } from '../utils/formatters';

const editTenantApi = getRouteApi('/tenants/$tenantName/edit');

/**
 * Route-level entry component for creating a new tenant onboarding request.
 * Wraps the form in a `ProtectedRoute` guard.
 * @returns The create form wrapped in a route authentication boundary.
 */
export function CreateTenantPage() {
  return (
    <ProtectedRoute>
      <TenantFormPage mode="create" />
    </ProtectedRoute>
  );
}

/**
 * Route-level entry component for editing an existing tenant onboarding request.
 * Reads the `tenantName` route parameter and passes it to the form in edit mode.
 * @returns The edit form wrapped in a route authentication boundary.
 */
export function EditTenantPage() {
  const { tenantName } = editTenantApi.useParams();
  return (
    <ProtectedRoute>
      <TenantFormPage mode="edit" tenantName={tenantName} />
    </ProtectedRoute>
  );
}

/**
 * Shared create/edit form for tenant onboarding requests.
 * Loads the form schema (and current tenant data when editing), handles field validation
 * with touch-based progressive disclosure, and submits create or update requests to the API.
 * @param mode - `"create"` for new requests; `"edit"` to update an existing tenant.
 * @param tenantName - The partition key of the tenant being edited. Required when `mode` is `"edit"`.
 * @returns The multi-section tenant form JSX, a loading panel, or an inline error message.
 */
function TenantFormPage({ mode, tenantName }: { mode: 'create' | 'edit'; tenantName?: string }) {
  const navigate = useNavigate();
  const [schema, setSchema] = useState<FormSchema | null>(null);
  const [form, setForm] = useState<TenantFormState | null>(null);
  const [error, setError] = useState('');
  const [hasSubmitted, setHasSubmitted] = useState(false);
  const [touched, setTouched] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  const markTouched = (field: string) => {
    setTouched((prev) => {
      if (prev.has(field)) return prev;
      const next = new Set(prev);
      next.add(field);
      return next;
    });
  };

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      try {
        const [schemaResponse, detailResponse] = await Promise.all([
          api.formSchema(),
          mode === 'edit' && tenantName ? api.getTenant(tenantName) : Promise.resolve(null),
        ]);
        if (!controller.signal.aborted) {
          setSchema(schemaResponse);
          if (detailResponse) {
            setForm(normalizeForm(detailResponse.tenant.FormData, schemaResponse));
          } else {
            setForm(normalizeForm(schemaResponse.defaults, schemaResponse));
          }
        }
      } catch (err) {
        if (!controller.signal.aborted) {
          setError(getErrorMessage(err));
        }
      } finally {
        if (!controller.signal.aborted) {
          setIsLoading(false);
        }
      }
    };
    void load();
    return () => controller.abort();
  }, [mode, tenantName]);

  const submitLabel = mode === 'create' ? 'Submit request' : 'Create updated version';

  if (!schema || !form) {
    return <InlineMessage tone="error" message={error || 'Unable to load form schema.'} />;
  }

  const validationErrors = validateTenantForm(form, schema);
  const visibleErrors: FormValidationErrors = {};
  for (const [key, message] of Object.entries(validationErrors)) {
    if (hasSubmitted || touched.has(key)) {
      visibleErrors[key as keyof FormValidationErrors] = message;
    }
  }

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const payload = sanitizeForm(form, schema);
    const payloadErrors = validateTenantForm(payload, schema);

    setHasSubmitted(true);
    setError('');
    setForm(payload);

    if (hasValidationErrors(payloadErrors)) {
      return;
    }

    setIsSaving(true);
    try {
      const response =
        mode === 'create'
          ? await api.createTenant(payload)
          : await api.updateTenant(tenantName ?? payload.project_name, payload);
      void navigate({
        to: '/tenants/$tenantName',
        params: { tenantName: response.tenant.PartitionKey },
      });
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return <Panel title="Loading form" />;
  }

  return (
    <form className="stack-lg" onSubmit={handleSubmit}>
      <section className="page-header">
        <div>
          <p className="eyebrow">{mode === 'create' ? 'New request' : 'Update request'}</p>
          <h2>{mode === 'create' ? 'Create tenant onboarding request' : `Update ${tenantName}`}</h2>
          <p>
            These inputs are versioned and used to generate environment tfvars for the platform
            deployment.
          </p>
        </div>
        <div className="button-row">
          <Link
            className="button button--ghost"
            params={mode === 'create' ? undefined : { tenantName: tenantName ?? '' }}
            to={mode === 'create' ? '/tenants' : '/tenants/$tenantName'}
          >
            Cancel
          </Link>
          <button className="button button--primary" disabled={isSaving} type="submit">
            {isSaving ? 'Saving...' : submitLabel}
          </button>
        </div>
      </section>

      {error ? <InlineMessage tone="error" message={error} /> : null}

      <section className="panel stack-md">
        <h3>Project identity</h3>
        <p className="section-intro">
          Define the tenant identity that reviewers and downstream automation will use across
          environments.
        </p>
        <div className="form-grid">
          <Field error={visibleErrors.project_name} info={schema.field_info.project_name}>
            <input
              aria-invalid={Boolean(visibleErrors.project_name)}
              autoCapitalize="off"
              autoCorrect="off"
              className={getInputClassName(visibleErrors.project_name)}
              disabled={mode === 'edit'}
              onBlur={() => markTouched('project_name')}
              onChange={(event) => setForm({ ...form, project_name: event.target.value })}
              minLength={schema.validation.project_name.min_length}
              pattern={schema.validation.project_name.pattern}
              placeholder={schema.field_info.project_name.placeholder}
              required={schema.validation.project_name.required}
              spellCheck={false}
              title={schema.validation.project_name.message}
              value={form.project_name}
            />
          </Field>
          <Field error={visibleErrors.display_name} info={schema.field_info.display_name}>
            <input
              aria-invalid={Boolean(visibleErrors.display_name)}
              className={getInputClassName(visibleErrors.display_name)}
              onBlur={() => markTouched('display_name')}
              onChange={(event) => setForm({ ...form, display_name: event.target.value })}
              required={schema.validation.display_name.required}
              title={schema.validation.display_name.message}
              value={form.display_name}
            />
          </Field>
          <Field error={visibleErrors.ministry} info={schema.field_info.ministry}>
            <select
              aria-invalid={Boolean(visibleErrors.ministry)}
              className={getInputClassName(visibleErrors.ministry)}
              onBlur={() => markTouched('ministry')}
              onChange={(event) => setForm({ ...form, ministry: event.target.value })}
              required={schema.validation.ministry.required}
              value={form.ministry}
            >
              {schema.ministries.map((ministry) => (
                <option key={ministry} value={ministry}>
                  {ministry}
                </option>
              ))}
            </select>
          </Field>
          <Field info={schema.field_info.department}>
            <input
              className="text-input"
              onChange={(event) => setForm({ ...form, department: event.target.value })}
              value={form.department}
            />
          </Field>
        </div>
      </section>

      <section className="panel stack-md">
        <h3>Services</h3>
        <p className="section-intro">
          Choose the platform services this tenant needs. Azure OpenAI or Document Intelligence must
          be enabled for every request.
        </p>
        {visibleErrors.services ? (
          <InlineMessage tone="error" message={visibleErrors.services} />
        ) : null}
        <div className="toggle-grid">
          <Toggle
            info={schema.field_info.openai_enabled}
            checked={form.openai_enabled}
            onChange={(checked) => {
              setForm({ ...form, openai_enabled: checked });
              markTouched('services');
            }}
          />
          <Toggle
            info={schema.field_info.ai_search_enabled}
            checked={form.ai_search_enabled}
            onChange={(checked) => {
              setForm({ ...form, ai_search_enabled: checked });
              markTouched('services');
            }}
          />
          <Toggle
            info={schema.field_info.document_intelligence_enabled}
            checked={form.document_intelligence_enabled}
            onChange={(checked) => {
              setForm({ ...form, document_intelligence_enabled: checked });
              markTouched('services');
            }}
          />
          <Toggle
            info={schema.field_info.speech_services_enabled}
            checked={form.speech_services_enabled}
            onChange={(checked) => {
              setForm({ ...form, speech_services_enabled: checked });
              markTouched('services');
            }}
          />
          <Toggle
            info={schema.field_info.cosmos_db_enabled}
            checked={form.cosmos_db_enabled}
            onChange={(checked) => {
              setForm({ ...form, cosmos_db_enabled: checked });
              markTouched('services');
            }}
          />
          <Toggle
            info={schema.field_info.storage_account_enabled}
            checked={form.storage_account_enabled}
            onChange={(checked) => {
              setForm({ ...form, storage_account_enabled: checked });
              markTouched('services');
            }}
          />
          <Toggle
            info={schema.field_info.key_vault_enabled}
            checked={form.key_vault_enabled}
            onChange={(checked) => {
              setForm({ ...form, key_vault_enabled: checked });
              markTouched('services');
            }}
          />
        </div>
      </section>

      {form.openai_enabled ? (
        <section className="panel stack-md">
          <h3>OpenAI model selection</h3>
          <p className="section-intro">
            Select the model families that will be requested when Azure OpenAI is enabled for this
            tenant.
          </p>
          {visibleErrors.model_families ? (
            <InlineMessage tone="error" message={visibleErrors.model_families} />
          ) : null}
          <div className="checkbox-grid">
            {Object.entries(schema.model_families).map(([key, family]) => (
              <label className="check-card" key={key}>
                <input
                  checked={form.model_families.includes(key)}
                  onChange={() => {
                    toggleModelFamily(key, form, setForm);
                    markTouched('model_families');
                  }}
                  type="checkbox"
                />
                <div>
                  <strong>{family.label}</strong>
                  <div className="cell-subtitle">
                    {family.models.map((model) => model.name).join(', ')}
                  </div>
                </div>
              </label>
            ))}
          </div>
          <div className="form-grid">
            <Field error={visibleErrors.capacity_tier} info={schema.field_info.capacity_tier}>
              <select
                aria-invalid={Boolean(visibleErrors.capacity_tier)}
                className={getInputClassName(visibleErrors.capacity_tier)}
                onBlur={() => markTouched('capacity_tier')}
                onChange={(event) => setForm({ ...form, capacity_tier: event.target.value })}
                required={schema.validation.capacity_tier.required}
                value={form.capacity_tier}
              >
                {Object.entries(schema.capacity_tiers).map(([key, value]) => (
                  <option key={key} value={key}>
                    {value.label}
                  </option>
                ))}
              </select>
            </Field>
          </div>
        </section>
      ) : null}

      <section className="panel stack-md">
        <h3>Gateway policies</h3>
        <p className="section-intro">
          Configure the tenant policies that will be applied at the gateway layer for incoming AI
          traffic.
        </p>
        <div className="toggle-grid">
          <Toggle
            info={schema.field_info.pii_redaction_enabled}
            checked={form.pii_redaction_enabled}
            onChange={(checked) => setForm({ ...form, pii_redaction_enabled: checked })}
          />
          <Toggle
            info={schema.field_info.logging_enabled}
            checked={form.logging_enabled}
            onChange={(checked) => setForm({ ...form, logging_enabled: checked })}
          />
          <Toggle
            info={schema.field_info.custom_rai_filters_enabled}
            checked={form.custom_rai_filters_enabled}
            onChange={(checked) => setForm({ ...form, custom_rai_filters_enabled: checked })}
          />
        </div>
      </section>

      <section className="panel stack-md">
        <h3>Tenant access</h3>
        <p className="section-intro">
          Assign the initial tenant members by access category. All seeded users must use @gov.bc.ca
          email addresses.
        </p>
        <div className="access-grid">
          <EmailListField
            error={visibleErrors.admin_users}
            info={schema.field_info.admin_users}
            inputPattern={schema.validation.admin_users.pattern}
            inputTitle={schema.validation.admin_users.message}
            inputType="email"
            values={form.admin_users}
            addLabel="Add admin user"
            onAdd={() => setForm({ ...form, admin_users: [...form.admin_users, ''] })}
            onBlur={() => markTouched('admin_users')}
            onChange={(index, value) => updateRoleEmail('admin_users', index, value, form, setForm)}
            onRemove={(index) => removeRoleEmail('admin_users', index, form, setForm)}
          />
          <EmailListField
            error={visibleErrors.write_users}
            info={schema.field_info.write_users}
            inputPattern={schema.validation.write_users.pattern}
            inputTitle={schema.validation.write_users.message}
            inputType="email"
            values={form.write_users}
            addLabel="Add write user"
            onAdd={() => setForm({ ...form, write_users: [...form.write_users, ''] })}
            onBlur={() => markTouched('write_users')}
            onChange={(index, value) => updateRoleEmail('write_users', index, value, form, setForm)}
            onRemove={(index) => removeRoleEmail('write_users', index, form, setForm)}
          />
          <EmailListField
            error={visibleErrors.read_users}
            info={schema.field_info.read_users}
            inputPattern={schema.validation.read_users.pattern}
            inputTitle={schema.validation.read_users.message}
            inputType="email"
            values={form.read_users}
            addLabel="Add read user"
            onAdd={() => setForm({ ...form, read_users: [...form.read_users, ''] })}
            onBlur={() => markTouched('read_users')}
            onChange={(index, value) => updateRoleEmail('read_users', index, value, form, setForm)}
            onRemove={(index) => removeRoleEmail('read_users', index, form, setForm)}
          />
        </div>
      </section>
    </form>
  );
}
