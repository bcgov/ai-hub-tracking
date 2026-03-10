import 'reflect-metadata';

import { Test } from '@nestjs/testing';
import type { INestApplication } from '@nestjs/common';

import { AppModule } from '../../src/app.module';
import { resetSettingsCache } from '../../src/config/settings';
import { SessionStoreService } from '../../src/storage/session-store.service';
import { TenantStoreService } from '../../src/storage/tenant-store.service';

type TestAppOptions = {
  authMode?: 'mock' | 'oidc';
};

export async function createTestApp(options: TestAppOptions = {}): Promise<INestApplication> {
  process.env.PORTAL_AUTH_MODE = options.authMode ?? 'mock';
  process.env.PORTAL_TABLE_STORAGE_CONNECTION_STRING = '';
  process.env.PORTAL_TABLE_STORAGE_ACCOUNT_URL = '';
  process.env.PORTAL_OIDC_DISCOVERY_URL =
    process.env.PORTAL_AUTH_MODE === 'oidc'
      ? 'https://example.invalid/realms/standard/.well-known/openid-configuration'
      : '';
  process.env.PORTAL_OIDC_CLIENT_ID = 'tenant-onboarding-portal';
  process.env.PORTAL_OIDC_CLIENT_SECRET = 'test-secret';
  process.env.PORTAL_MOCK_USER_ROLES = 'portal-admin';
  resetSettingsCache();
  SessionStoreService.resetInMemoryStore();
  TenantStoreService.resetInMemoryStore();

  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleRef.createNestApplication();
  await app.init();
  return app;
}
