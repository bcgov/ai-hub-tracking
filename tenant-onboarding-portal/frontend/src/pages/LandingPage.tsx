import { Navigate } from '@tanstack/react-router';
import { useShallow } from 'zustand/react/shallow';

import { useAuthStore } from '../stores/auth';

/**
 * Renders the unauthenticated landing page with a sign-in prompt and portal overview.
 * Redirects authenticated users to the tenant list automatically.
 * @returns The landing page JSX, or a redirect element when the user is already authenticated.
 */
export function LandingPage() {
  const { isAuthenticated, login } = useAuthStore(
    useShallow((state) => ({
      isAuthenticated: state.isAuthenticated,
      login: state.login,
    })),
  );

  if (isAuthenticated) {
    return <Navigate to="/tenants" />;
  }

  return (
    <div className="hero-grid">
      <section className="hero-card hero-card--primary">
        <p className="eyebrow">Tenant onboarding</p>
        <h2>Request AI platform resources without editing Terraform by hand.</h2>
        <p>
          The NestJS backend owns the OIDC flow, maintains the portal session, and stores request
          data for review and approval.
        </p>
        <div className="hero-actions">
          <button className="button button--primary" onClick={() => void login()} type="button">
            Sign in with BCGov
          </button>
          <a className="button button--ghost" href="/healthz">
            Service health
          </a>
        </div>
      </section>
      <section className="hero-card">
        <h3>Portal flow</h3>
        <ol className="number-list">
          <li>Sign in through the backend and receive an HttpOnly portal session.</li>
          <li>Submit or revise tenant onboarding requests through the portal API.</li>
          <li>Admins review pending versions and approve or reject them with notes.</li>
        </ol>
      </section>
    </div>
  );
}
