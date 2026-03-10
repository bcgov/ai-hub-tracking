import { create } from 'zustand';

import { ApiError, api } from '../api';
import { buildLoginUrl, buildLogoutUrl, getAuthConfig } from '../services/token-service';
import type { AuthConfigResponse, SessionUser } from '../types';

const SESSION_REFRESH_INTERVAL_MS = 2 * 60 * 1000;

let sessionRefreshTimer: number | null = null;

/**
 * Clears the active session refresh interval timer.
 * Safe to call even when no timer is running.
 */
function stopSessionRefreshTimer() {
  if (sessionRefreshTimer !== null) {
    window.clearInterval(sessionRefreshTimer);
    sessionRefreshTimer = null;
  }
}

/**
 * Starts the session refresh interval timer if one is not already running.
 * Calls the provided `refreshSession` function at the configured interval.
 * @param refreshSession - Async function that refreshes the current session.
 */
function ensureSessionRefreshTimer(refreshSession: () => Promise<void>) {
  if (sessionRefreshTimer !== null) {
    return;
  }

  sessionRefreshTimer = window.setInterval(() => {
    void refreshSession();
  }, SESSION_REFRESH_INTERVAL_MS);
}

type AuthState = {
  config: AuthConfigResponse | null;
  isInitialized: boolean;
  isAuthenticated: boolean;
  isAdmin: boolean;
  isLoading: boolean;
  user: SessionUser | null;
  error: string | null;
  initAuth: () => Promise<void>;
  refreshSession: () => Promise<void>;
  login: () => Promise<void>;
  logout: () => Promise<void>;
};

/**
 * Returns the default unauthenticated state slice for the auth store.
 * Used to reset authentication fields on logout or session error.
 * @returns Partial auth state with `isAuthenticated`, `isAdmin`, and `user` cleared.
 */
function resetAuthState() {
  return {
    isAuthenticated: false,
    isAdmin: false,
    user: null,
  };
}

export const useAuthStore = create<AuthState>((set, get) => ({
  config: null,
  isInitialized: false,
  isAuthenticated: false,
  isAdmin: false,
  isLoading: false,
  user: null,
  error: null,

  /**
   * Initializes the auth store by loading the auth config and refreshing the current session.
   * No-op if the store is already initialized. Always sets `isInitialized` on completion.
   */
  initAuth: async () => {
    if (get().isInitialized) {
      return;
    }

    set({ isLoading: true, error: null });

    try {
      const config = await getAuthConfig();
      set({ config });

      await get().refreshSession();
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Authentication bootstrap failed.';
      set({ ...resetAuthState(), error: message });
    } finally {
      set({ isInitialized: true, isLoading: false });
    }
  },

  /**
   * Refreshes the current session from the server and updates authentication state.
   * Starts the periodic refresh timer when authenticated, stops it when unauthenticated.
   * On a 401 response, clears the auth state silently without reporting an error.
   */
  refreshSession: async () => {
    try {
      const session = await api.session();
      set({
        isAuthenticated: session.authenticated,
        isAdmin: session.isAdmin,
        user: session.user,
      });

      if (session.authenticated) {
        ensureSessionRefreshTimer(get().refreshSession);
      } else {
        stopSessionRefreshTimer();
      }
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        stopSessionRefreshTimer();
        set(resetAuthState());
        return;
      }

      const message = error instanceof Error ? error.message : 'Unable to load session.';
      set({ ...resetAuthState(), error: message });
    }
  },

  /**
   * Redirects the browser to the backend login URL, preserving the current page as the post-login return target.
   * Loads auth config if not already cached.
   */
  login: async () => {
    const config = get().config ?? (await getAuthConfig());
    set({ config, isLoading: true, error: null });

    try {
      window.location.assign(buildLoginUrl(window.location.href));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to sign in.';
      set({ error: message });
    } finally {
      set({ isLoading: false });
    }
  },

  /**
   * Clears local authentication state, stops the refresh timer, and redirects the browser to the backend logout URL.
   */
  logout: async () => {
    set({ isLoading: true, error: null });

    try {
      stopSessionRefreshTimer();
      set(resetAuthState());
      window.location.assign(buildLogoutUrl(`${window.location.origin}/`));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to sign out.';
      set({ error: message });
    } finally {
      set({ isLoading: false });
    }
  },
}));

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    stopSessionRefreshTimer();
  });
}
