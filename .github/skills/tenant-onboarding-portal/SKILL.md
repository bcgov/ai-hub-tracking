---
name: tenant-onboarding-portal
description: Guidance for modifying the tenant onboarding portal in ai-hub-tracking. Use when changing the NestJS backend, React/Vite frontend, mock auth or Keycloak integration, Azure Table Storage behavior, or Playwright end-to-end coverage for tenant onboarding workflows.
---

# Tenant Onboarding Portal

Use this skill when working in `tenant-onboarding-portal/`.

## Scope

- Backend: `tenant-onboarding-portal/backend/src/`
- Frontend: `tenant-onboarding-portal/frontend/src/`
- Local run tooling: `tenant-onboarding-portal/backend/run-local.sh`
- Tests: `tenant-onboarding-portal/backend/tests/`
- Portal infra and deployment wiring: `tenant-onboarding-portal/infra/`, `.github/workflows/`

## Architecture

The portal is a NestJS backend that serves a built React SPA.

- The backend owns API routes, auth validation, Azure Table Storage access, and tfvars generation.
- The frontend authenticates through `/api/auth/config` and `/api/session`, then calls `/api/...` routes with bearer tokens.
- Built frontend assets are copied into `tenant-onboarding-portal/backend/frontend-dist/` for deployment and E2E runs.

## Auth Model

- Production-style auth uses Keycloak bearer-token validation.
- Local and E2E runs can use `PORTAL_AUTH_MODE=mock`.
- Mock auth should preserve the same authorization boundaries as real auth:
  - authenticated user session
  - admin role checks via `oidc_admin_role`

Prefer adding behavior inside the auth abstraction rather than bypassing route guards or hardcoding UI shortcuts.

## Testing Guidance

- Backend tests use Vitest and Supertest.
- E2E tests use Playwright against the built frontend served by the backend.
- Prefer mock auth for portal E2E tests.
- Keep Playwright selectors semantic:
  - labels
  - button text
  - headings
  - links

Avoid brittle CSS selectors unless no accessible selector exists.

## Storage Guidance

- Azure Table Storage is the main persistence layer.
- Local tests should continue using the in-memory fallback unless the task explicitly needs Azure storage behavior.
- Preserve request versioning semantics when changing create/update flows.

## Code Formatting and Linting

Both backend and frontend share the **same Prettier config** at `tenant-onboarding-portal/.prettierrc`:

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2
}
```

- **Prettier** formats all TypeScript source files. Always run `format` after making code changes.
- **ESLint** enforces code quality. Both use ESLint 9 flat config with `typescript-eslint` and `eslint-config-prettier` (disables formatting rules that conflict with Prettier).
- The backend config is at `backend/eslint.config.mjs`; the frontend config is at `frontend/eslint.config.js`.
- **Pre-commit hooks** run ESLint + Prettier check automatically on changed `backend/` and `frontend/` TypeScript files. A commit will be rejected if lint or format checks fail.

**After every code change**, run from the respective directory:

```bash
npm run format   # auto-format with Prettier
npm run lint     # ESLint check (or lint:fix to auto-fix)
```

## JSDoc Documentation

JSDoc is **mandatory** for every function and method in the codebase. This applies to:

- Every exported function or class method in the backend and frontend
- Every internal (non-exported) function or class method
- React component functions

JSDoc is **not required** for:

- Inline arrow function callbacks (e.g. inside `useEffect`, `map`, event handlers)
- Test files (`*.spec.ts`)

### Required JSDoc structure

```ts
/**
 * One-sentence description of what the function does.
 *
 * @param paramName - Description of the parameter. No `{Type}` — TypeScript owns types.
 * @returns Description of the return value when non-void.
 * @throws Description of the error when the function explicitly documents a failure path.
 */
```

Rules:
- A **description sentence is required** on every JSDoc block — never leave it empty.
- Use `@param name - description` format (dash separator, no type annotation).
- Add `@returns` when the function returns a meaningful non-void value.
- Add `@throws` only when you explicitly document an error condition.
- Do **not** add `{Type}` annotations in `@param` or `@returns` — TypeScript provides the types.

### ESLint enforcement

Both packages enforce JSDoc via `eslint-plugin-jsdoc`. The relevant rules are set to **error**:

- `jsdoc/require-jsdoc` on `FunctionDeclaration` and `MethodDefinition`
- `jsdoc/require-description` — blocks without a description sentence fail lint
- `jsdoc/require-param` and `jsdoc/require-returns` — missing tags for documented params/returns fail lint
- `jsdoc/require-param-type` and `jsdoc/require-returns-type` are **off** (TypeScript owns types)

Running `npm run lint` will report any missing JSDoc blocks.

## NestJS Backend Best Practices

- Use NestJS modules, controllers, services, and guards — do not put logic directly in `main.ts`.
- Dependency injection: always inject services through constructor parameters with proper NestJS providers.
- Use `@Injectable()` for services, `@Controller()` for route handlers, `@Module()` for feature modules.
- Decorate request DTOs with class-validator decorators and use `ValidationPipe` globally.
- Keep controller methods thin — delegate business logic to service classes.
- Use `@UseGuards()` for auth enforcement; never skip guards with inline token inspection in controllers.
- `no-explicit-any` is a lint warning (not error) — prefer typed interfaces and DTOs instead.

## React Frontend Best Practices

- State management uses Zustand stores — keep store slices focused and co-located with feature code.
- Routing uses TanStack Router — define routes in files expected by the router plugin.
- Use `@bcgov/design-system-react-components` components before reaching for custom HTML or Bootstrap directly.
- Prefer React Query or similar data-fetching patterns over raw `useEffect` for async state.
- `no-explicit-any` is a lint warning — always type API responses and component props.
- React Hooks plugin enforces rules of hooks — do not call hooks conditionally.

## Implementation Rules

1. Preserve the `/api/...` contract used by the React SPA unless the task explicitly requires coordinated frontend and backend changes.
2. Keep auth behavior centralized in the backend token validator and frontend auth store.
3. Prefer environment-driven test modes over special-case test-only code paths scattered through controllers and components.
4. When adding E2E coverage, verify the full user journey end to end instead of only checking page load.
5. When changing tenant request fields, update validation, API types, frontend form handling, and tfvars generation together.
6. **Always run `npm run format` after every code change** — the pre-commit hook will reject unformatted code.

## Useful Commands

```bash
# Backend
cd tenant-onboarding-portal/backend
npm run format        # auto-format source with Prettier
npm run lint          # ESLint check
npm run lint:fix      # ESLint auto-fix
npm run format:check  # Prettier dry-run (used by pre-commit)
npm run build
npm test
npm run e2e

# Frontend
cd tenant-onboarding-portal/frontend
npm run format        # auto-format source with Prettier
npm run lint          # ESLint check
npm run lint:fix      # ESLint auto-fix
npm run format:check  # Prettier dry-run (used by pre-commit)
npm run build
npm test
```