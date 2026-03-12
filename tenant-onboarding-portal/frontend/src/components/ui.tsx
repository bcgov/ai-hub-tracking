import { startTransition, useCallback, useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';

import type { FormSchema } from '../types';
import type { HubEnv, TenantCredentialsResponse, ApimTenantInfoResponse } from '../types';
import { api } from '../api';
import { getInputClassName } from '../utils/formatters';

type FieldInfo = FormSchema['field_info'][keyof FormSchema['field_info']];

/**
 * Renders a bordered section panel with a muted title.
 * @param title - Heading text displayed inside the panel.
 * @returns A `<section>` element styled as a panel.
 */
export function Panel({ title }: { title: string }) {
  return (
    <section className="panel">
      <p className="muted">{title}</p>
    </section>
  );
}

/**
 * Renders a full-page hero card with a title and description.
 * Used for prominent status messages that occupy the main content area.
 * @param title - Heading text for the hero card.
 * @param description - Body text providing detail below the heading.
 * @returns A hero grid layout with a single primary card.
 */
export function FullPageMessage({ title, description }: { title: string; description: string }) {
  return (
    <div className="hero-grid">
      <section className="hero-card hero-card--primary">
        <h2>{title}</h2>
        <p>{description}</p>
      </section>
    </div>
  );
}

/**
 * Renders an empty state section with a title, description, and optional action element.
 * @param title - Heading text for the empty state.
 * @param description - Explanatory text shown below the heading.
 * @param action - Optional React node (e.g. a button) displayed below the description.
 * @returns A panel element styled as an empty state placeholder.
 */
export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <section className="panel empty-state">
      <h3>{title}</h3>
      <p>{description}</p>
      {action}
    </section>
  );
}

/**
 * Renders a coloured inline notification banner with a single message string.
 * @param tone - Visual tone: `'error'` for errors, `'info'` for informational notices.
 * @param message - Text content to display inside the banner.
 * @returns A `<div>` styled as an inline message with the appropriate tone class.
 */
export function InlineMessage({ tone, message }: { tone: 'error' | 'info'; message: string }) {
  return <div className={`inline-message inline-message--${tone}`}>{message}</div>;
}

/**
 * Renders a labelled form field wrapping a child input element, with optional error and help text.
 * @param info - Field metadata from the form schema providing label, placeholder, and description.
 * @param children - The input or control element to embed inside the label.
 * @param error - Optional validation error message displayed below the child element.
 * @returns A `<label>` element containing the field header, child, error, and help text.
 */
export function Field({
  info,
  children,
  error,
}: {
  info: FieldInfo;
  children: ReactNode;
  error?: string;
}) {
  return (
    <label className="field">
      <FieldHeader info={info} />
      {children}
      {error ? <span className="field__error">{error}</span> : null}
      <span className="field__help">{info.description}</span>
    </label>
  );
}

/**
 * Renders a field header row containing the field label and an info tooltip icon.
 * @param info - Field metadata from the form schema providing label and details text.
 * @returns A `<span>` containing the label text and the tooltip icon.
 */
export function FieldHeader({ info }: { info: FieldInfo }) {
  return (
    <span className="field__header">
      <span className="field__label">{info.label}</span>
      <FieldInfoIcon info={info} />
    </span>
  );
}

/**
 * Renders a keyboard-focusable info icon with a tooltip showing the field details text.
 * @param info - Field metadata providing the `details` text shown in the tooltip.
 * @returns A `<span>` containing the icon and a tooltip element.
 */
function FieldInfoIcon({ info }: { info: FieldInfo }) {
  return (
    <span className="field-info" tabIndex={0}>
      <i aria-hidden="true" className="bi bi-info-circle"></i>
      <span className="field-info__tooltip" role="tooltip">
        {info.details}
      </span>
    </span>
  );
}

/**
 * Renders a card-style toggle (checkbox) with a field header and description.
 * @param info - Field metadata providing label and description text.
 * @param checked - Whether the toggle is currently in the checked state.
 * @param onChange - Callback invoked with the new boolean value when the toggle changes.
 * @returns A `<label>` element styled as a toggle card.
 */
export function Toggle({
  info,
  checked,
  onChange,
}: {
  info: FieldInfo;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="toggle-card">
      <input
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        type="checkbox"
      />
      <div className="toggle-card__body">
        <FieldHeader info={info} />
        <span className="field__help">{info.description}</span>
      </div>
    </label>
  );
}

let emailKeyCounter = 0;

/**
 * Renders a dynamic list of email input fields with add and remove controls.
 * Maintains stable React keys across additions and removals using an internal counter ref.
 * @param info - Field metadata providing label, description, and placeholder text.
 * @param values - Current array of email strings.
 * @param addLabel - Label text for the add-another button.
 * @param error - Optional validation error message displayed above the inputs.
 * @param inputPattern - Optional HTML `pattern` attribute applied to each input.
 * @param inputTitle - Optional HTML `title` attribute for input validation tooltip text.
 * @param inputType - Input type, either `'email'` or `'text'`.
 * @param onAdd - Callback invoked when the user clicks the add button.
 * @param onBlur - Optional callback invoked when an input loses focus.
 * @param onChange - Callback invoked with the index and new value when an input changes.
 * @param onRemove - Callback invoked with the index of the entry to remove.
 * @returns A `<section>` containing the dynamic email input list.
 */
export function EmailListField({
  info,
  values,
  addLabel,
  error,
  inputPattern,
  inputTitle,
  inputType,
  onAdd,
  onBlur,
  onChange,
  onRemove,
}: {
  info: FieldInfo;
  values: string[];
  addLabel: string;
  error?: string;
  inputPattern?: string;
  inputTitle?: string;
  inputType?: 'email' | 'text';
  onAdd: () => void;
  onBlur?: () => void;
  onChange: (index: number, value: string) => void;
  onRemove: (index: number) => void;
}) {
  const keysRef = useRef<string[]>([]);
  while (keysRef.current.length < values.length) {
    keysRef.current.push(`email-${emailKeyCounter++}`);
  }

  const handleRemove = (index: number) => {
    keysRef.current.splice(index, 1);
    onRemove(index);
  };

  return (
    <section className={`role-card stack-sm ${error ? 'role-card--error' : ''}`}>
      <FieldHeader info={info} />
      {error ? <span className="field__error">{error}</span> : null}
      <p className="field__help">{info.description}</p>
      <div className="stack-sm">
        {values.map((email, index) => (
          <div className="inline-input-row" key={keysRef.current[index]}>
            <input
              aria-invalid={Boolean(error)}
              className={getInputClassName(error)}
              onBlur={onBlur}
              onChange={(event) => onChange(index, event.target.value)}
              pattern={inputPattern}
              placeholder={info.placeholder ?? 'name@gov.bc.ca'}
              title={inputTitle}
              type={inputType}
              value={email}
            />
            <button
              className="button button--ghost"
              onClick={() => handleRemove(index)}
              type="button"
            >
              Remove
            </button>
          </div>
        ))}
      </div>
      <button className="button button--ghost" onClick={onAdd} type="button">
        {addLabel}
      </button>
    </section>
  );
}

/**
 * Renders a label-value row for use in summary and review layouts.
 * @param label - Descriptive label for the data field.
 * @param value - The data value to display; may be any React node.
 * @returns A `<div>` containing a label span and a value span.
 */
export function SummaryRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="summary-row">
      <span className="summary-row__label">{label}</span>
      <span className="summary-row__value">{value}</span>
    </div>
  );
}

/**
 * Renders a list of tag badges, or a muted fallback message when the list is empty.
 * @param items - Array of string items to display as tags.
 * @returns A tag list `<div>` when items are present, or a muted `<p>` when empty.
 */
export function TagList({ items }: { items: string[] }) {
  if (items.length === 0) {
    return <p className="muted">No services selected.</p>;
  }

  return (
    <div className="tag-list">
      {items.map((item) => (
        <span className="tag" key={item}>
          {item}
        </span>
      ))}
    </div>
  );
}

const HUB_ENVS: HubEnv[] = ['dev', 'test', 'prod'];

interface EnvCredState {
  data: TenantCredentialsResponse | null;
  loading: boolean;
  error: string | null;
}

interface EnvInfoState {
  data: ApimTenantInfoResponse | null;
  loading: boolean;
  error: string | null;
  expanded: boolean;
}

/**
 * Renders a credentials panel for an approved tenant, showing APIM primary/secondary
 * keys per environment with copy-to-clipboard support, rotation metadata, and tenant-info.
 * @param root0 - Component props.
 * @param root0.tenantName - The tenant partition key used to fetch credentials and tenant info.
 * @returns JSX element containing the credentials panel.
 */
export function CredentialsPanel({ tenantName }: { tenantName: string }) {
  const [activeEnv, setActiveEnv] = useState<HubEnv>('dev');
  const [credState, setCredState] = useState<Record<HubEnv, EnvCredState>>({
    dev: { data: null, loading: false, error: null },
    test: { data: null, loading: false, error: null },
    prod: { data: null, loading: false, error: null },
  });
  const [infoState, setInfoState] = useState<Record<HubEnv, EnvInfoState>>({
    dev: { data: null, loading: false, error: null, expanded: false },
    test: { data: null, loading: false, error: null, expanded: false },
    prod: { data: null, loading: false, error: null, expanded: false },
  });
  const [copied, setCopied] = useState<Record<string, boolean>>({});
  const fetchedEnvs = useRef<Set<HubEnv>>(new Set());

  const fetchCreds = useCallback(
    async (env: HubEnv) => {
      if (fetchedEnvs.current.has(env)) return;
      fetchedEnvs.current.add(env);
      startTransition(() => {
        setCredState((prev) => ({ ...prev, [env]: { data: null, loading: true, error: null } }));
      });
      try {
        const data = await api.getCredentials(tenantName, env);
        startTransition(() => {
          setCredState((prev) => ({ ...prev, [env]: { data, loading: false, error: null } }));
        });
      } catch (err: unknown) {
        const status = (err as { status?: number }).status;
        let msg = 'Failed to load credentials';
        if (status === 403) msg = 'You do not have permission to view credentials for this tenant';
        else if (status === 503)
          msg = 'Credentials not available for this environment (not configured)';
        else if (status === 409) msg = 'Tenant is not yet approved';
        startTransition(() => {
          setCredState((prev) => ({ ...prev, [env]: { data: null, loading: false, error: msg } }));
        });
        // Remove from fetched so user can retry
        fetchedEnvs.current.delete(env);
      }
    },
    [tenantName],
  );

  useEffect(() => {
    void fetchCreds(activeEnv);
  }, [activeEnv, fetchCreds]);

  const handleCopy = useCallback((key: string, keyId: string) => {
    void navigator.clipboard.writeText(key).then(() => {
      setCopied((prev) => ({ ...prev, [keyId]: true }));
      setTimeout(() => {
        setCopied((prev) => ({ ...prev, [keyId]: false }));
      }, 2000);
    });
  }, []);

  const toggleInfo = useCallback(
    async (env: HubEnv) => {
      const current = infoState[env];
      if (!current.expanded && !current.data && !current.loading) {
        setInfoState((prev) => ({
          ...prev,
          [env]: { ...prev[env], expanded: true, loading: true, error: null },
        }));
        try {
          const data = await api.getApimTenantInfo(tenantName, env);
          setInfoState((prev) => ({
            ...prev,
            [env]: { data, loading: false, error: null, expanded: true },
          }));
        } catch (err: unknown) {
          const status = (err as { status?: number }).status;
          let msg = 'Failed to load tenant info from APIM';
          if (status === 503) msg = 'APIM not configured for this environment';
          setInfoState((prev) => ({
            ...prev,
            [env]: { ...prev[env], loading: false, error: msg, expanded: true },
          }));
        }
      } else {
        setInfoState((prev) => ({
          ...prev,
          [env]: { ...prev[env], expanded: !current.expanded },
        }));
      }
    },
    [infoState, tenantName],
  );

  const cred = credState[activeEnv];
  const info = infoState[activeEnv];

  return (
    <section className="panel stack-md">
      <h3>API Credentials</h3>
      <div className="tab-bar" role="tablist">
        {HUB_ENVS.map((env) => (
          <button
            className={`tab-button${activeEnv === env ? ' tab-button--active' : ''}`}
            key={env}
            onClick={() => {
              setActiveEnv(env);
            }}
            role="tab"
            aria-selected={activeEnv === env}
            type="button"
          >
            {env.charAt(0).toUpperCase() + env.slice(1)}
          </button>
        ))}
      </div>

      <div role="tabpanel">
        {cred.loading && <p className="muted">Loading credentials&hellip;</p>}
        {cred.error && <p className="inline-message inline-message--error">{cred.error}</p>}
        {cred.data && (
          <div className="stack-md">
            <div className="credential-row">
              <span className="credential-label">Primary Key</span>
              <span className="credential-value credential-value--masked">••••••••••••••••</span>
              <button
                className="button button--secondary button--sm"
                type="button"
                onClick={() => {
                  handleCopy(cred.data!.primary_key, `${activeEnv}-primary`);
                }}
              >
                {copied[`${activeEnv}-primary`] ? '✓ Copied' : 'Copy'}
              </button>
            </div>
            <div className="credential-row">
              <span className="credential-label">Secondary Key</span>
              <span className="credential-value credential-value--masked">••••••••••••••••</span>
              <button
                className="button button--secondary button--sm"
                type="button"
                onClick={() => {
                  handleCopy(cred.data!.secondary_key, `${activeEnv}-secondary`);
                }}
              >
                {copied[`${activeEnv}-secondary`] ? '✓ Copied' : 'Copy'}
              </button>
            </div>

            {cred.data.rotation && (
              <details className="rotation-metadata">
                <summary>Rotation metadata</summary>
                <pre>{JSON.stringify(cred.data.rotation, null, 2)}</pre>
              </details>
            )}

            <div className="tenant-info-toggle">
              <button
                className="button button--secondary button--sm"
                type="button"
                onClick={() => {
                  void toggleInfo(activeEnv);
                }}
              >
                {info.expanded ? 'Hide tenant info' : 'Show tenant info'}
              </button>
            </div>

            {info.expanded && (
              <div className="tenant-info-panel stack-md">
                {info.loading && <p className="muted">Loading tenant info&hellip;</p>}
                {info.error && <p className="inline-message inline-message--error">{info.error}</p>}
                {info.data && (
                  <>
                    <p>
                      <strong>Base URL:</strong> {info.data.base_url}
                    </p>
                    <h4>Services</h4>
                    <table className="data-table">
                      <thead>
                        <tr>
                          <th>Service</th>
                          <th>Enabled</th>
                        </tr>
                      </thead>
                      <tbody>
                        {Object.entries(info.data.services).map(([svc, service]) => (
                          <tr key={svc}>
                            <td>{svc}</td>
                            <td>{service.enabled ? 'Yes' : 'No'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    <h4>Models</h4>
                    <table className="data-table">
                      <thead>
                        <tr>
                          <th>Model</th>
                          <th>Deployment ID</th>
                          <th>Capacity</th>
                          <th>Scale</th>
                        </tr>
                      </thead>
                      <tbody>
                        {info.data.models.map((m) => (
                          <tr key={m.name}>
                            <td>
                              <div className="table-cell-stack">
                                <span>{m.name}</span>
                                <span className="table-cell-meta">Version {m.model_version}</span>
                              </div>
                            </td>
                            <td>{m.deployment}</td>
                            <td>{m.capacity}</td>
                            <td>{m.scale_type}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </section>
  );
}
