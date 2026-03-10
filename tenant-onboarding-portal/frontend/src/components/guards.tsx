import type { ReactNode } from 'react';
import { Navigate } from '@tanstack/react-router';
import { useShallow } from 'zustand/react/shallow';

import { useAuthStore } from '../stores/auth';
import { FullPageMessage } from './ui';

/**
 * Renders its children when the user is authenticated, otherwise redirects to the landing page.
 * @param children - Protected child nodes to render when access is granted.
 * @returns The child content or a `<Navigate>` redirect.
 */
export function ProtectedRoute({ children }: { children: ReactNode }) {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  if (!isAuthenticated) {
    return <Navigate to="/" />;
  }
  return children;
}

/**
 * Renders its children only when the user is both authenticated and holds the admin role.
 * Redirects unauthenticated users to the landing page and shows an access-denied message for non-admin users.
 * @param children - Admin-only child nodes to render when access is granted.
 * @returns The child content, a `<Navigate>` redirect, or an access-denied message.
 */
export function AdminRoute({ children }: { children: ReactNode }) {
  const { isAdmin, isAuthenticated } = useAuthStore(
    useShallow((state) => ({
      isAdmin: state.isAdmin,
      isAuthenticated: state.isAuthenticated,
    })),
  );

  if (!isAuthenticated) {
    return <Navigate to="/" />;
  }
  if (!isAdmin) {
    return (
      <FullPageMessage
        description="Your token is valid, but it does not include the configured portal admin role."
        title="Admin access required"
      />
    );
  }

  return children;
}
