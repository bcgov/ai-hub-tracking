import { Request, Response, NextFunction } from 'express';
import { Injectable, NestMiddleware, Logger } from '@nestjs/common';

@Injectable()
export class HTTPLoggerMiddleware implements NestMiddleware {
  private logger = new Logger('HTTP');

  /**
   * Logs an HTTP access line for every response, including the HTTP method,
   * URL, status code, response body size, response time in milliseconds,
   * and the user-agent header.
   *
   * @param request - The Express request object.
   * @param response - The Express response object whose `finish` event is observed.
   * @param next - The next middleware function in the Express pipeline.
   */
  use(request: Request, response: Response, next: NextFunction): void {
    const { method, originalUrl } = request;
    const startTime = Date.now();

    response.on('finish', () => {
      const { statusCode } = response;
      const contentLength = response.get('content-length') || '-';
      const responseTimeMs = Math.max(0, Date.now() - startTime);
      const hostedHttpLogFormat = `${method} ${originalUrl} ${statusCode} ${contentLength} ${responseTimeMs}ms - ${request.get(
        'user-agent',
      )}`;
      this.logger.log(hostedHttpLogFormat);
    });
    next();
  }
}
