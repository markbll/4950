/// <reference types="vitest/config" />
import { defineConfig, loadEnv, type Plugin, type ViteDevServer } from 'vite';
import react from '@vitejs/plugin-react';

/**
 * Dev-only middleware: server-renders each page with the same renderPage()
 * used by the production prerender, so `npm run dev` matches the built HTML.
 */
function devSsr(): Plugin {
  return {
    name: 'bigcat-dev-ssr',
    apply: 'serve',
    configureServer(server: ViteDevServer) {
      return () => {
        server.middlewares.use(async (req, res, next) => {
          const url = req.originalUrl ?? '/';
          if (req.method !== 'GET' || url.startsWith('/api/') || /\.[a-z0-9]+(\?|$)/i.test(url.split('?')[0] ?? '')) {
            return next();
          }
          try {
            const mod = await server.ssrLoadModule('/src/entry-server.tsx');
            const page = await mod.renderPage(url.split('?')[0], {
              scripts: ['/src/entry-client.ts'],
              styles: [],
              preloads: [],
            });
            const html = await server.transformIndexHtml(url, page.html);
            res.statusCode = page.status;
            res.setHeader('Content-Type', 'text/html; charset=utf-8');
            res.end(html);
          } catch (err) {
            server.ssrFixStacktrace(err as Error);
            next(err);
          }
        });
      };
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    plugins: [react(), devSsr()],
    appType: 'custom',
    define: {
      __BUILD_YEAR__: JSON.stringify(new Date().getFullYear()),
    },
    server: {
      proxy: {
        '/api': env.DEV_API_PROXY || 'http://127.0.0.1:8000',
      },
    },
    build: {
      manifest: true,
      outDir: 'dist',
      emptyOutDir: true,
      assetsDir: 'assets',
      cssCodeSplit: true,
      rollupOptions: {
        input: 'src/entry-client.ts',
      },
    },
    ssr: {
      noExternal: ['@fontsource/inter', '@fontsource/space-grotesk'],
    },
    test: {
      environment: 'node',
      include: ['tests/**/*.test.{ts,tsx}'],
    },
  };
});
