import 'reflect-metadata';

import { Logger } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';

import { bootstrap } from './app';
import { getSettings } from './config/settings';

const logger = new Logger('NestApplication');

/**
 * Determines the active storage backend mode from the provided settings.
 * Returns `'connection-string'` when an explicit Azure Table Storage connection
 * string is configured, `'managed-identity'` when only an account URL is
 * provided, or `'in-memory'` when no Azure storage credentials are present.
 *
 * @param settings - The application settings object returned by `getSettings()`.
 * @returns A string identifying the storage mode in use.
 */
function storageMode(settings: ReturnType<typeof getSettings>): string {
  if (settings.tableStorageConnectionString) {
    return 'connection-string';
  }

  if (settings.tableStorageAccountUrl) {
    return 'managed-identity';
  }

  return 'in-memory';
}

bootstrap()
  .then(async (app: NestExpressApplication) => {
    const settings = getSettings();
    const parsedPort = Number.parseInt(process.env.PORT ?? '8000', 10);
    const port = Number.isFinite(parsedPort) ? parsedPort : 8000;

    await app.listen(port);

    logger.log(`${settings.appName} listening on ${await app.getUrl()}`);
    logger.log(
      `Azure Table storage mode: ${storageMode(settings)}; connectionStringPresent=${settings.tableStorageConnectionString ? 'true' : 'false'}; accountUrlPresent=${settings.tableStorageAccountUrl ? 'true' : 'false'}`,
    );
    logger.log(`Process startup took ${process.uptime()} seconds`);
  })
  .catch((error: unknown) => {
    logger.error(error);
  });
