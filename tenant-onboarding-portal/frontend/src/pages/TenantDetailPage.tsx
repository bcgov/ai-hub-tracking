import { useEffect, useState } from 'react';
import { Link, getRouteApi } from '@tanstack/react-router';

import { api } from '../api';
import { ProtectedRoute } from '../components/guards';
import { InlineMessage, Panel, SummaryRow, TagList } from '../components/ui';
import type { FormSchema, TenantDetailResponse } from '../types';
import { normalizeForm } from '../utils/form-helpers';
import { formatDate, getErrorMessage, stringValue } from '../utils/formatters';

const tenantDetailApi = getRouteApi('/tenants/$tenantName');

/**
 * Route-level entry component for the tenant detail view.
 * Wraps the detail content in a `ProtectedRoute` guard.
 * @returns The protected detail view wrapped in a route authentication boundary.
 */
export function TenantDetailPage() {
  return (
    <ProtectedRoute>
      <TenantDetailContent />
    </ProtectedRoute>
  );
}

/**
 * Fetches tenant detail and form schema in parallel, then renders a summary grid,
 * Azure-generated tfvars per environment, and a version history table.
 * @returns The detail page JSX, or an inline error message if loading fails.
 */
function TenantDetailContent() {
  const { tenantName } = tenantDetailApi.useParams();
  const [detail, setDetail] = useState<TenantDetailResponse | null>(null);
  const [schema, setSchema] = useState<FormSchema | null>(null);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      try {
        const [detailResponse, schemaResponse] = await Promise.all([
          api.getTenant(tenantName),
          api.formSchema(),
        ]);
        if (!controller.signal.aborted) {
          setDetail(detailResponse);
          setSchema(schemaResponse);
          setError('');
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
  }, [tenantName]);

  if (isLoading) {
    return <Panel title="Loading tenant" />;
  }

  if (error || !detail || !schema) {
    return <InlineMessage tone="error" message={error || 'Tenant not found.'} />;
  }

  const formData = normalizeForm(detail.tenant.FormData, schema);
  const generatedTfvars = detail.tenant.GeneratedTfvars ?? {};

  return (
    <div className="stack-lg">
      <section className="page-header">
        <div>
          <p className="eyebrow">Tenant request</p>
          <h2>{detail.tenant.DisplayName}</h2>
          <p>{detail.tenant.PartitionKey}</p>
        </div>
        <div className="button-row">
          <Link className="button button--ghost" to="/tenants">
            Back to requests
          </Link>
          <Link
            className="button button--primary"
            params={{ tenantName: detail.tenant.PartitionKey }}
            to="/tenants/$tenantName/edit"
          >
            Create updated version
          </Link>
        </div>
      </section>

      <section className="detail-grid">
        <div className="panel stack-md">
          <h3>Request summary</h3>
          <SummaryRow
            label="Status"
            value={
              <span className={`status-badge status-badge--${detail.tenant.Status}`}>
                {detail.tenant.Status}
              </span>
            }
          />
          <SummaryRow label="Ministry" value={detail.tenant.Ministry} />
          <SummaryRow label="Department" value={stringValue(formData.department)} />
          <SummaryRow label="Submitted by" value={detail.tenant.SubmittedBy} />
          <SummaryRow label="Created" value={formatDate(detail.tenant.CreatedAt)} />
          <SummaryRow label="Review notes" value={detail.tenant.ReviewNotes || 'No review notes'} />
        </div>

        <div className="panel stack-md">
          <h3>Selected services</h3>
          <TagList
            items={
              [
                formData.openai_enabled ? 'Azure OpenAI' : null,
                formData.ai_search_enabled ? 'AI Search' : null,
                formData.document_intelligence_enabled ? 'Document Intelligence' : null,
                formData.speech_services_enabled ? 'Speech Services' : null,
                formData.cosmos_db_enabled ? 'Cosmos DB' : null,
                formData.storage_account_enabled ? 'Storage Account' : null,
                formData.key_vault_enabled ? 'Key Vault' : null,
              ].filter(Boolean) as string[]
            }
          />
          <SummaryRow
            label="Model families"
            value={(formData.model_families ?? []).join(', ') || 'None'}
          />
          <SummaryRow label="Capacity tier" value={stringValue(formData.capacity_tier)} />
          <SummaryRow
            label="Gateway policies"
            value={
              [
                formData.pii_redaction_enabled ? 'PII redaction' : null,
                formData.logging_enabled ? 'Logging' : null,
                formData.custom_rai_filters_enabled ? 'Custom RAI filters' : null,
              ]
                .filter(Boolean)
                .join(', ') || 'None'
            }
          />
          <SummaryRow
            label="Admin users"
            value={(formData.admin_users ?? []).join(', ') || 'None'}
          />
          <SummaryRow
            label="Write users"
            value={(formData.write_users ?? []).join(', ') || 'None'}
          />
          <SummaryRow label="Read users" value={(formData.read_users ?? []).join(', ') || 'None'} />
        </div>
      </section>

      <section className="panel stack-md">
        <h3>Generated tfvars</h3>
        {Object.keys(generatedTfvars).length === 0 ? (
          <p className="muted">No generated tfvars were attached to this request.</p>
        ) : (
          <div className="stack-md">
            {Object.entries(generatedTfvars).map(([environment, content]) => (
              <div key={environment} className="code-block-wrap">
                <div className="code-block__header">{environment}.tfvars</div>
                <pre className="code-block">{content}</pre>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="panel stack-md">
        <h3>Version history</h3>
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Version</th>
                <th>Status</th>
                <th>Submitted</th>
                <th>Reviewed by</th>
              </tr>
            </thead>
            <tbody>
              {detail.versions.map((version) => (
                <tr key={version.RowKey}>
                  <td>{version.RowKey}</td>
                  <td>
                    <span className={`status-badge status-badge--${version.Status}`}>
                      {version.Status}
                    </span>
                  </td>
                  <td>{formatDate(version.CreatedAt)}</td>
                  <td>{version.ReviewedBy || 'Not reviewed'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
