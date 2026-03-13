import { MiddlewareConsumer, Module, RequestMethod } from '@nestjs/common';

import { AuthSessionService } from './auth/session.service';
import { TokenValidatorService } from './auth/token-validator.service';
import { AppController } from './app.controller';
import { SessionStoreService } from './storage/session-store.service';
import { TenantStoreService } from './storage/tenant-store.service';
import { HubKeyVaultService } from './services/hub-keyvault.service';
import { HTTPLoggerMiddleware } from './middleware/req.res.logger';
@Module({
  controllers: [AppController],
  providers: [
    AuthSessionService,
    SessionStoreService,
    TokenValidatorService,
    TenantStoreService,
    HubKeyVaultService,
  ],
})
export class AppModule {
  /**
   * Registers the HTTP request logger middleware on all routes, excluding
   * the metrics and health check endpoints.
   *
   * @param consumer - The NestJS middleware consumer used to bind middleware to routes.
   */
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(HTTPLoggerMiddleware)
      .exclude(
        { path: 'metrics', method: RequestMethod.ALL },
        { path: 'health', method: RequestMethod.ALL },
      )
      .forRoutes('{*path}');
  }
}
