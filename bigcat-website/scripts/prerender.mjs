/**
 * Prerender every public route to static HTML (plus 404.html).
 * Requires: client build (dist/ + manifest) and SSR build (dist-ssr/).
 */
import { mkdirSync, writeFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { dist, loadManifest, loadServer, outFile } from './lib.mjs';

const server = await loadServer();
const manifest = loadManifest();
const { routes, notFoundRoute, siteConfig, outstandingFacts, renderPage, INLINE_BOOT } = server;

// Production gate: refuse to build production HTML with required business facts missing.
const missing = outstandingFacts().filter((f) => f.required);
if (siteConfig.env === 'production' && missing.length && process.env.ALLOW_TODOS !== '1') {
  console.error('✖ Production build blocked — required business facts are still TODO in src/data/business.ts:');
  for (const f of missing) console.error(`  - ${f.key}: ${f.note}`);
  console.error('Fill them in (or set ALLOW_TODOS=1 for a deliberate override).');
  process.exit(1);
}

const entry = manifest['src/entry-client.ts'];
if (!entry) throw new Error('entry-client missing from manifest');

const collectCss = (key, seen = new Set()) => {
  const chunk = manifest[key];
  if (!chunk || seen.has(key)) return [];
  seen.add(key);
  return [...(chunk.css ?? []), ...(chunk.imports ?? []).flatMap((k) => collectCss(k, seen))];
};
const collectImports = (key, seen = new Set()) => {
  const chunk = manifest[key];
  if (!chunk || seen.has(key)) return [];
  seen.add(key);
  return [chunk.file, ...(chunk.imports ?? []).flatMap((k) => collectImports(k, seen))];
};

const islandKeys = {
  checkup: 'src/islands/CheckupForm.tsx',
  contact: 'src/islands/ContactForm.tsx',
  subscribe: 'src/islands/SubscribeForm.tsx',
};
const entryImports = new Set(collectImports('src/entry-client.ts'));
// react-dom/client is a dynamic import of the entry (loaded only when an island hydrates).
const runtimeChunks = (entry.dynamicImports ?? []).filter((k) => !Object.values(islandKeys).includes(k)).flatMap((k) => collectImports(k));
// Preload the above-the-fold form islands (and React) on the pages that have them.
// The footer subscribe island is deliberately NOT preloaded — it hydrates on approach.
const eager = ['checkup', 'contact'];
const islandPreloads = Object.fromEntries(
  Object.entries(islandKeys).map(([name, key]) => [
    name,
    eager.includes(name) ? [...new Set([...collectImports(key), ...runtimeChunks])].filter((f) => !entryImports.has(f)).map((f) => `/${f}`) : [],
  ]),
);

const fontFiles = readdirSync(path.join(dist, 'assets')).filter(
  (f) => /^inter-latin-400-normal.*\.woff2$/.test(f) || /^space-grotesk-latin-700-normal.*\.woff2$/.test(f),
);

const assets = {
  scripts: [`/${entry.file}`],
  styles: [...new Set(collectCss('src/entry-client.ts'))].map((c) => `/${c}`),
  preloads: [...entryImports].filter((f) => f !== entry.file).map((f) => `/${f}`),
  islandPreloads,
  fonts: fontFiles.map((f) => `/assets/${f}`),
};

let count = 0;
for (const route of routes) {
  const page = await renderPage(route.path, assets);
  if (page.status !== 200) throw new Error(`Route ${route.path} rendered status ${page.status}`);
  const file = outFile(route.path);
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, page.html);
  count++;
}
const nf = await renderPage(notFoundRoute.path + '-does-not-exist', assets);
writeFileSync(path.join(dist, '404.html'), nf.html);

const cspHash = createHash('sha256').update(INLINE_BOOT).digest('base64');
writeFileSync(path.join(dist, '.csp-inline-hash.txt'), `'sha256-${cspHash}'\n`);

console.log(`✔ Prerendered ${count} routes + 404.html (env: ${siteConfig.env}, site: ${siteConfig.siteUrl})`);
console.log(`  Inline boot script CSP hash: 'sha256-${cspHash}'`);
if (missing.length) console.warn(`⚠ ${missing.length} required business fact(s) still TODO — visible markers are shown on this ${siteConfig.env} build.`);
