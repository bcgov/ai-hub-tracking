import { Test } from '@nestjs/testing';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { HTTPLoggerMiddleware } from './req.res.logger';
import { Request, Response } from 'express';
import { Logger } from '@nestjs/common';

describe('HTTPLoggerMiddleware', () => {
  let middleware: HTTPLoggerMiddleware;
  let _logger: Logger;
  let dateNowSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [HTTPLoggerMiddleware, Logger],
    }).compile();

    middleware = module.get<HTTPLoggerMiddleware>(HTTPLoggerMiddleware);
    _logger = module.get<Logger>(Logger);
  });

  afterEach(() => {
    dateNowSpy?.mockRestore();
  });

  it('should log the correct information', () => {
    const request: Request = {
      method: 'GET',
      originalUrl: '/test',
      get: () => 'Test User Agent',
    } as unknown as Request;

    const response: Response = {
      statusCode: 200,
      get: () => '100',
      on: (event: string, cb: () => void) => {
        if (event === 'finish') {
          cb();
        }
      },
    } as unknown as Response;

    const loggerSpy = vi.spyOn(middleware['logger'], 'log');
    dateNowSpy = vi.spyOn(Date, 'now').mockReturnValueOnce(1000).mockReturnValueOnce(1042);

    middleware.use(request, response, () => {});

    expect(loggerSpy).toHaveBeenCalledWith(`GET /test 200 100 42ms - Test User Agent`);
  });
});
