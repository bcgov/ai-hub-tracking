import {
  createRootRoute,
  createRoute,
  createRouter,
  lazyRouteComponent,
} from '@tanstack/react-router';

import { RootLayout } from './components/RootLayout';

const rootRoute = createRootRoute({ component: RootLayout });

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: lazyRouteComponent(() => import('./pages/LandingPage'), 'LandingPage'),
});

const tenantsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/tenants',
  component: lazyRouteComponent(() => import('./pages/TenantDashboardPage'), 'TenantDashboardPage'),
});

const newTenantRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/tenants/new',
  component: lazyRouteComponent(() => import('./pages/TenantFormPage'), 'CreateTenantPage'),
});

const tenantDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/tenants/$tenantName',
  component: lazyRouteComponent(() => import('./pages/TenantDetailPage'), 'TenantDetailPage'),
});

const editTenantRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/tenants/$tenantName/edit',
  component: lazyRouteComponent(() => import('./pages/TenantFormPage'), 'EditTenantPage'),
});

const adminDashboardRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/admin/dashboard',
  component: lazyRouteComponent(() => import('./pages/AdminPages'), 'AdminDashboardPage'),
});

const adminReviewRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/admin/review/$tenantName/$version',
  component: lazyRouteComponent(() => import('./pages/AdminPages'), 'AdminReviewPage'),
});

const routeTree = rootRoute.addChildren([
  indexRoute,
  tenantsRoute,
  newTenantRoute,
  tenantDetailRoute,
  editTenantRoute,
  adminDashboardRoute,
  adminReviewRoute,
]);

export const router = createRouter({ routeTree });

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router;
  }
}
