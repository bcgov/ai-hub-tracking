import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    exclude: ['tests/e2e/**', 'node_modules/**', 'dist/**'],
    include: ['tests/**/*.test.ts', 'src/**/*.spec.ts', 'src/**/*.test.ts'],
  },
});
