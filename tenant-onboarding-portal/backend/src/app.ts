import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import express, { type Request, type Response } from 'express';
import helmet from 'helmet';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

import { AppModule } from './app.module';
import { customLogger } from './common/logger.config';
import { getSettings } from './config/settings';

/**
 * Sets cache-control headers on a response to prevent caching of sensitive API data.
 *
 * @param response - The Express response object to apply no-store headers to.
 */
function setNoStoreHeaders(response: Response): void {
  response.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  response.setHeader('Pragma', 'no-cache');
  response.setHeader('Expires', '0');
  response.setHeader('Surrogate-Control', 'no-store');
}

/**
 * Determines whether the given request origin is permitted by the configured
 * list of allowed CORS origins. Allows all origins when no list is configured.
 *
 * @param origin - The origin header value from the incoming request, or undefined for same-origin requests.
 * @param allowedOrigins - The list of explicitly allowed origin strings from application settings.
 * @returns True when the origin is allowed, false otherwise.
 */
function resolveCorsOrigin(origin: string | undefined, allowedOrigins: string[]): boolean {
  if (!origin) {
    return true;
  }

  if (allowedOrigins.length === 0) {
    return true;
  }

  return allowedOrigins.includes(origin);
}

/**
 * Applies security middleware to the NestJS application: removes the `x-powered-by`
 * header, adds Helmet CSP/HSTS headers, configures CORS with origin validation,
 * and attaches no-store cache headers to all `/api` and `/healthz` routes.
 *
 * @param app - The NestExpressApplication instance to configure.
 */
function configureSecurity(app: NestExpressApplication): void {
  const expressApp = app.getHttpAdapter().getInstance();
  const settings = getSettings();

  expressApp.disable('x-powered-by');
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          imgSrc: ["'self'", 'data:'],
          fontSrc: ["'self'", 'data:'],
          connectSrc: ["'self'"],
          frameAncestors: ["'none'"],
        },
      },
      crossOriginEmbedderPolicy: false,
    }),
  );
  app.enableCors({
    origin: (origin, callback) => {
      if (resolveCorsOrigin(origin, settings.corsAllowedOrigins)) {
        callback(null, true);
        return;
      }

      callback(new Error(`Origin ${origin} is not allowed by CORS`));
    },
    credentials: true,
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type'],
    maxAge: 86400,
  });
  expressApp.use(
    ['/api', '/healthz'],
    (_request: Request, response: Response, next: () => void) => {
      setNoStoreHeaders(response);
      next();
    },
  );
}

/**
 * Returns an HTML error page shown when the frontend production build is missing.
 *
 * @returns An HTML string with instructions to build the frontend.
 */
function frontendMissingHtml(): string {
  return '<h1>Frontend build missing</h1><p>Run <code>npm run build:frontend</code> in <code>tenant-onboarding-portal/backend</code>.</p>';
}

/**
 * Resolves the local frontend development server URL from the
 * `PORTAL_FRONTEND_DEV_URL` environment variable, defaulting to
 * `http://localhost:5173` when the variable is not set.
 *
 * @returns The configured or default frontend development server URL.
 */
function frontendDevUrl(): string {
  const configured = (process.env.PORTAL_FRONTEND_DEV_URL ?? '').trim().replace(/\/$/, '');
  if (configured) {
    return configured;
  }

  return 'http://localhost:5173';
}

/**
 * Returns true when the request is coming from a local browser
 * (localhost, 127.0.0.1, or ::1), used to proxy requests to the
 * Vite dev server during local development.
 *
 * @param request - The Express request object to inspect.
 * @returns True when the request hostname is a loopback address.
 */
function isLocalBrowserRequest(request: Request): boolean {
  const host = request.hostname.toLowerCase();
  return host === 'localhost' || host === '127.0.0.1' || host === '::1';
}

/**
 * Registers the SPA (Single-Page Application) routing middleware.
 * In local development, browser requests are proxied to the Vite dev server.
 * In production, static frontend assets are served and all non-API routes
 * respond with `index.html` to support client-side routing.
 *
 * @param app - The NestExpressApplication instance to configure.
 */
function configureSpa(app: NestExpressApplication): void {
  const expressApp = app.getHttpAdapter().getInstance();
  const frontendDistDir = join(process.cwd(), 'frontend-dist');
  const frontendAssetsDir = join(frontendDistDir, 'assets');
  const frontendIndexFile = join(frontendDistDir, 'index.html');
  const devUrl = frontendDevUrl();

  expressApp.get(
    /^(?!\/api(?:\/|$)|\/healthz(?:\/|$)).*/,
    (request: Request, response: Response, next: () => void) => {
      if (!isLocalBrowserRequest(request)) {
        next();
        return;
      }

      if (devUrl) {
        response.redirect(302, `${devUrl}${request.originalUrl}`);
        return;
      }

      next();
    },
  );

  if (existsSync(frontendAssetsDir)) {
    expressApp.use('/assets', express.static(frontendAssetsDir));
  }

  if (existsSync(frontendDistDir)) {
    expressApp.use(express.static(frontendDistDir, { index: false }));
  }

  expressApp.get(
    /^(?!\/api(?:\/|$)|\/healthz(?:\/|$)|\/assets(?:\/|$)).*/,
    (_request: Request, response: Response) => {
      if (existsSync(frontendIndexFile)) {
        setNoStoreHeaders(response);
        response.sendFile(frontendIndexFile);
        return;
      }

      response.status(503).send(frontendMissingHtml());
    },
  );
}

/**
 * Applies all application-level configuration (security, shutdown hooks, proxy
 * trust, and SPA routing) to the given NestJS application instance.
 *
 * @param app - The NestExpressApplication instance to configure.
 * @returns The fully configured application instance.
 */
function configureApp(app: NestExpressApplication): NestExpressApplication {
  configureSecurity(app);
  app.enableShutdownHooks();
  app.set('trust proxy', 1);
  configureSpa(app);
  return app;
}

/**
 * Creates and fully configures the NestJS application instance.
 * Called from `main.ts` to obtain the app before calling `app.listen()`.
 *
 * @returns The configured NestExpressApplication ready to start listening.
 */
export async function bootstrap(): Promise<NestExpressApplication> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    logger: customLogger,
  });
  return configureApp(app);
}
