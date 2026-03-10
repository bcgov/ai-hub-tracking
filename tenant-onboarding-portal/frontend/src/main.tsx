import '@bcgov/bc-sans/css/BC_Sans.css';
import 'bootstrap-icons/font/bootstrap-icons.css';

import { Component, StrictMode } from 'react';
import type { ErrorInfo, ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from '@tanstack/react-router';

import { router } from './router';
import './scss/styles.scss';
import './styles.css';
import { useAuthStore } from './stores/auth';

class ErrorBoundary extends Component<{ children: ReactNode }, { hasError: boolean }> {
  /**
   * Initialises the error boundary with a default `hasError: false` state.
   * @param props - Standard React children prop passed to the boundary.
   */
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  /**
   * Updates state to indicate a render error has been caught.
   * @returns New state object with `hasError` set to `true`.
   */
  static getDerivedStateFromError(): { hasError: boolean } {
    return { hasError: true };
  }

  /**
   * Logs uncaught render errors to the console for diagnostic purposes.
   * @param error - The error that caused the render to fail.
   * @param info - React error info object containing the component stack.
   */
  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('Uncaught render error:', error, info);
  }

  /**
   * Renders the children normally, or a fallback error message when a render error has been caught.
   * @returns JSX for the normal subtree or the error fallback UI.
   */
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: '2rem', textAlign: 'center' }}>
          <h1>Something went wrong</h1>
          <p>Please refresh the page or contact support if the issue persists.</p>
          <button onClick={() => window.location.reload()} type="button">
            Refresh
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

/**
 * Mounts the React application into the `#root` DOM element with strict mode and error boundary wrappers.
 */
function renderApp() {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <ErrorBoundary>
        <RouterProvider router={router} />
      </ErrorBoundary>
    </StrictMode>,
  );
}

void useAuthStore.getState().initAuth().finally(renderApp);
