import { useEffect, useState } from 'react';
import { Link } from '@tanstack/react-router';

import { api } from '../api';
import { ProtectedRoute } from '../components/guards';
import { EmptyState, InlineMessage, Panel } from '../components/ui';
import type { TenantRecord } from '../types';
import { formatDate, getErrorMessage } from '../utils/formatters';

/**
 * Route-level entry component for the tenant dashboard.
 * Wraps the dashboard content in a `ProtectedRoute` guard.
 * @returns The protected dashboard wrapped in a route authentication boundary.
 */
export function TenantDashboardPage() {
  return (
    <ProtectedRoute>
      <TenantDashboardContent />
    </ProtectedRoute>
  );
}

/**
 * Fetches and renders the current user's tenant request list.
 * Displays a loading indicator, an empty state with a create action, or a sortable data table.
 * @returns The dashboard panel, empty state, or data table JSX depending on load state.
 */
function TenantDashboardContent() {
  const [items, setItems] = useState<TenantRecord[]>([]);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      try {
        const response = await api.listTenants();
        if (!controller.signal.aborted) {
          setItems(response.items);
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
  }, []);

  if (isLoading) {
    return <Panel title="Loading requests" />;
  }

  return (
    <div className="stack-lg">
      <section className="page-header">
        <div>
          <p className="eyebrow">Workspace</p>
          <h2>My tenant requests</h2>
          <p>View current tenant versions and open a request for a new onboarding package.</p>
        </div>
        <Link className="button button--primary" to="/tenants/new">
          New request
        </Link>
      </section>
      {error ? <InlineMessage tone="error" message={error} /> : null}
      {items.length === 0 ? (
        <EmptyState
          action={
            <Link className="button button--primary" to="/tenants/new">
              Create request
            </Link>
          }
          description="Start with a tenant request and the portal will generate the platform configuration inputs."
          title="No requests yet"
        />
      ) : (
        <section className="panel">
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Tenant</th>
                  <th>Ministry</th>
                  <th>Status</th>
                  <th>Updated</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {items.map((tenant) => (
                  <tr key={`${tenant.PartitionKey}-${tenant.RowKey}`}>
                    <td>
                      <strong>{tenant.DisplayName}</strong>
                      <div className="cell-subtitle">{tenant.PartitionKey}</div>
                    </td>
                    <td>{tenant.Ministry}</td>
                    <td>
                      <span className={`status-badge status-badge--${tenant.Status}`}>
                        {tenant.Status}
                      </span>
                    </td>
                    <td>{formatDate(tenant.UpdatedAt ?? tenant.CreatedAt)}</td>
                    <td>
                      <Link
                        className="text-link"
                        params={{ tenantName: tenant.PartitionKey }}
                        to="/tenants/$tenantName"
                      >
                        View request
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}
    </div>
  );
}
