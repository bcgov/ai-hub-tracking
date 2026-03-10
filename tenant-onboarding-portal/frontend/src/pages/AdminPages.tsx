import { useEffect, useState } from 'react';
import { Link, getRouteApi, useNavigate } from '@tanstack/react-router';

import { api } from '../api';
import { AdminRoute } from '../components/guards';
import { InlineMessage, Panel, SummaryRow } from '../components/ui';
import type { AdminDashboardResponse, TenantRecord } from '../types';
import { formatDate, getErrorMessage } from '../utils/formatters';

const adminReviewApi = getRouteApi('/admin/review/$tenantName/$version');

/**
 * Route-level entry component for the admin dashboard.
 * Wraps the dashboard content in an `AdminRoute` guard.
 * @returns The protected admin dashboard wrapped in a role-based route boundary.
 */
export function AdminDashboardPage() {
  return (
    <AdminRoute>
      <AdminDashboardContent />
    </AdminRoute>
  );
}

/**
 * Fetches and renders the admin review queue alongside the current tenant registry.
 * Displays pending submission statistics, a reviewable list of pending items, and a full tenant overview table.
 * @returns The admin dashboard JSX, or an inline error message if loading fails.
 */
function AdminDashboardContent() {
  const [data, setData] = useState<AdminDashboardResponse | null>(null);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      try {
        const response = await api.adminDashboard();
        if (!controller.signal.aborted) {
          setData(response);
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
  }, []);

  if (isLoading) {
    return <Panel title="Loading admin queue" />;
  }

  if (error || !data) {
    return <InlineMessage tone="error" message={error || 'Unable to load admin dashboard.'} />;
  }

  return (
    <div className="stack-lg">
      <section className="page-header">
        <div>
          <p className="eyebrow">Administration</p>
          <h2>Review queue</h2>
          <p>
            Approve or reject submitted tenant versions and inspect the current state across all
            tenants.
          </p>
        </div>
      </section>

      <section className="stats-grid">
        <div className="stat-card">
          <span>Pending reviews</span>
          <strong>{data.pending.length}</strong>
        </div>
        <div className="stat-card">
          <span>Current tenants</span>
          <strong>{data.all_tenants.length}</strong>
        </div>
      </section>

      <section className="panel stack-md">
        <h3>Pending submissions</h3>
        {data.pending.length === 0 ? (
          <p className="muted">No pending submissions.</p>
        ) : (
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Tenant</th>
                  <th>Version</th>
                  <th>Submitted by</th>
                  <th>Submitted</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {data.pending.map((item) => (
                  <tr key={`${item.PartitionKey}-${item.RowKey}`}>
                    <td>{item.DisplayName}</td>
                    <td>{item.RowKey}</td>
                    <td>{item.SubmittedBy}</td>
                    <td>{formatDate(item.CreatedAt)}</td>
                    <td>
                      <Link
                        className="text-link"
                        params={{
                          tenantName: item.PartitionKey,
                          version: item.RowKey,
                        }}
                        to="/admin/review/$tenantName/$version"
                      >
                        Review
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="panel stack-md">
        <h3>Current tenant versions</h3>
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Tenant</th>
                <th>Status</th>
                <th>Updated</th>
                <th>Open</th>
              </tr>
            </thead>
            <tbody>
              {data.all_tenants.map((item) => (
                <tr key={`${item.PartitionKey}-${item.RowKey}`}>
                  <td>{item.DisplayName}</td>
                  <td>
                    <span className={`status-badge status-badge--${item.Status}`}>
                      {item.Status}
                    </span>
                  </td>
                  <td>{formatDate(item.UpdatedAt ?? item.CreatedAt)}</td>
                  <td>
                    <Link
                      className="text-link"
                      params={{ tenantName: item.PartitionKey }}
                      to="/tenants/$tenantName"
                    >
                      Open
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

/**
 * Route-level entry component for the admin review page.
 * Wraps the review content in an `AdminRoute` guard.
 * @returns The protected review page wrapped in a role-based route boundary.
 */
export function AdminReviewPage() {
  return (
    <AdminRoute>
      <AdminReviewContent />
    </AdminRoute>
  );
}

/**
 * Fetches a specific tenant version for admin review and handles approve or reject decisions.
 * Renders submission metadata, generated tfvars per environment, and a notes textarea with action buttons.
 * @returns The review page JSX, or an inline error message if loading fails.
 */
function AdminReviewContent() {
  const { tenantName, version } = adminReviewApi.useParams();
  const navigate = useNavigate();
  const [tenant, setTenant] = useState<TenantRecord | null>(null);
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      try {
        const response = await api.adminReview(tenantName, version);
        if (!controller.signal.aborted) {
          setTenant(response.tenant_request);
          setNotes(response.tenant_request.ReviewNotes ?? '');
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
  }, [tenantName, version]);

  const handleDecision = async (action: 'approve' | 'reject') => {
    setIsSaving(true);
    setError('');
    try {
      if (action === 'approve') {
        await api.approveRequest(tenantName, version, notes);
      } else {
        await api.rejectRequest(tenantName, version, notes);
      }
      void navigate({ to: '/admin/dashboard' });
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return <Panel title="Loading review" />;
  }

  if (error || !tenant) {
    return <InlineMessage tone="error" message={error || 'Unable to load review record.'} />;
  }

  return (
    <div className="stack-lg">
      <section className="page-header">
        <div>
          <p className="eyebrow">Admin review</p>
          <h2>{tenant.DisplayName}</h2>
          <p>
            Reviewing version {tenant.RowKey} for {tenant.PartitionKey}
          </p>
        </div>
        <Link className="button button--ghost" to="/admin/dashboard">
          Back to queue
        </Link>
      </section>

      <section className="detail-grid">
        <div className="panel stack-md">
          <h3>Submission details</h3>
          <SummaryRow label="Submitted by" value={tenant.SubmittedBy} />
          <SummaryRow
            label="Status"
            value={
              <span className={`status-badge status-badge--${tenant.Status}`}>{tenant.Status}</span>
            }
          />
          <SummaryRow label="Created" value={formatDate(tenant.CreatedAt)} />
          <SummaryRow label="Ministry" value={tenant.Ministry} />
        </div>
        <div className="panel stack-md">
          <h3>Review notes</h3>
          <textarea
            className="textarea-input"
            onChange={(event) => setNotes(event.target.value)}
            rows={10}
            value={notes}
          />
          {error ? <InlineMessage tone="error" message={error} /> : null}
          <div className="button-row">
            <button
              className="button button--danger"
              disabled={isSaving}
              onClick={() => void handleDecision('reject')}
              type="button"
            >
              Reject
            </button>
            <button
              className="button button--primary"
              disabled={isSaving}
              onClick={() => void handleDecision('approve')}
              type="button"
            >
              Approve
            </button>
          </div>
        </div>
      </section>

      <section className="panel stack-md">
        <h3>Generated tfvars</h3>
        {Object.entries(tenant.GeneratedTfvars ?? {}).map(([environment, content]) => (
          <div key={environment} className="code-block-wrap">
            <div className="code-block__header">{environment}.tfvars</div>
            <pre className="code-block">{content}</pre>
          </div>
        ))}
      </section>
    </div>
  );
}
