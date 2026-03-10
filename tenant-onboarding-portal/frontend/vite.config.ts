import { defineConfig, loadEnv } from 'vite';
import { fileURLToPath, URL } from 'node:url';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'PORTAL_');
  const apiPort = env.PORTAL_API_PORT || '8000';

  return {
    plugins: [react(), tsconfigPaths()],
    server: {
      host: true,
      port: 5173,
      proxy: {
        '/api': `http://localhost:${apiPort}`,
        '/healthz': `http://localhost:${apiPort}`,
      },
    },
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
        '~bootstrap': fileURLToPath(new URL('./node_modules/bootstrap', import.meta.url)),
      },
    },
    css: {
      preprocessorOptions: {
        scss: {
          silenceDeprecations: ['mixed-decls', 'color-functions', 'global-builtin', 'import'],
        },
      },
    },
  };
});
