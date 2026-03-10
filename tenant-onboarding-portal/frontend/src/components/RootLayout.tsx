import { Outlet, useLocation, useNavigate } from '@tanstack/react-router';
import { useShallow } from 'zustand/react/shallow';
import { Footer, Header } from '@bcgov/design-system-react-components';

import { useAuthStore } from '../stores/auth';
import { InlineMessage } from './ui';

/**
 * Application shell that assembles the header, navigation bar, main content area, and footer.
 * Renders navigation links conditionally based on the user's authentication and admin status.
 * Displays a global error banner when the auth store reports an error.
 * @returns The full page layout wrapping the router outlet.
 */
export function RootLayout() {
  const { error, isAuthenticated, isAdmin, isLoading, login, logout, user } = useAuthStore(
    useShallow((state) => ({
      error: state.error,
      isAuthenticated: state.isAuthenticated,
      isAdmin: state.isAdmin,
      isLoading: state.isLoading,
      login: state.login,
      logout: state.logout,
      user: state.user,
    })),
  );

  const navigate = useNavigate();
  const location = useLocation();

  const isOnMyRequests =
    location.pathname === '/tenants' ||
    (location.pathname.startsWith('/tenants/') && location.pathname !== '/tenants/new');
  const isOnNewRequest = location.pathname === '/tenants/new';
  const isOnAdminQueue = location.pathname.startsWith('/admin');

  return (
    <div className="app-layout">
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>

      <div className="app-header">
        <div className="app-header__top">
          <Header title="AI Services Hub Tenant Portal" titleElement="h1" />
          {isAuthenticated ? (
            <div className="app-session app-session--header">
              <div className="app-session__user">
                <i aria-hidden="true" className="bi bi-person-circle"></i>
                <span>{user?.name ?? user?.email}</span>
              </div>
              <button
                className="app-session__action"
                disabled={isLoading}
                onClick={() => void logout()}
                type="button"
              >
                <i aria-hidden="true" className="bi bi-box-arrow-right"></i>
                <span>Sign Out</span>
              </button>
            </div>
          ) : (
            <div className="app-toolbar__auth app-toolbar__auth--header">
              <button
                className="app-session__action"
                disabled={isLoading}
                onClick={() => void login()}
                type="button"
              >
                <span>Sign in with BCGov</span>
              </button>
            </div>
          )}
        </div>
        {isAuthenticated ? (
          <div className="app-toolbar">
            <div className="app-toolbar__inner">
              <nav aria-label="Portal navigation" className="app-nav">
                <button
                  className={`app-nav__button ${isOnMyRequests ? 'app-nav__button--active' : ''}`}
                  onClick={() => void navigate({ to: '/tenants' })}
                  type="button"
                >
                  <i aria-hidden="true" className="bi bi-list-task"></i>
                  <span>My Requests</span>
                </button>
                <button
                  className={`app-nav__button ${isOnNewRequest ? 'app-nav__button--active' : ''}`}
                  onClick={() => void navigate({ to: '/tenants/new' })}
                  type="button"
                >
                  <i aria-hidden="true" className="bi bi-plus-circle"></i>
                  <span>New Request</span>
                </button>
                {isAdmin ? (
                  <button
                    className={`app-nav__button ${isOnAdminQueue ? 'app-nav__button--active' : ''}`}
                    onClick={() => void navigate({ to: '/admin/dashboard' })}
                    type="button"
                  >
                    <i aria-hidden="true" className="bi bi-shield-check"></i>
                    <span>Admin Queue</span>
                  </button>
                ) : null}
              </nav>
            </div>
          </div>
        ) : null}
      </div>

      <div className="app-content">
        <main className="page" id="main-content">
          {error ? <InlineMessage tone="error" message={error} /> : null}
          <Outlet />
        </main>
      </div>

      <div className="app-footer-wrapper">
        <Footer hideAcknowledgement />
      </div>
    </div>
  );
}
