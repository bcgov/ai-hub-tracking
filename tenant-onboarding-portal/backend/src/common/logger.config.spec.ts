import { describe, expect, it, vi } from 'vitest';

import { customLogger } from './logger.config';

describe('CustomLogger', () => {
  it('should be defined', () => {
    expect(customLogger).toBeDefined();
  });

  it('should log a message', () => {
    if (typeof customLogger.verbose !== 'function') {
      throw new Error('Expected custom logger to expose a verbose method');
    }

    const spy = vi.spyOn(customLogger, 'verbose');
    customLogger.verbose('Test message');
    expect(spy).toHaveBeenCalledWith('Test message');
    spy.mockRestore();
  });
});
