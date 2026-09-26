/** Generate dist/sitemap.xml and dist/robots.txt from the route registry. */
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { dist, loadServer } from './lib.mjs';

const { routes, siteConfig } = await loadServer();
const today = new Date().toISOString().slice(0, 10);
const url = (p) => `${siteConfig.siteUrl}${p}`;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

const entries = routes
  .filter((r) => !r.noindex)
  .map(
    (r) => `  <url>
    <loc>${esc(url(r.path))}</loc>
    <lastmod>${today}</lastmod>
    <changefreq>${r.changefreq}</changefreq>
    <priority>${r.priority.toFixed(1)}</priority>
  </url>`,
  )
  .join('\n');

writeFileSync(
  path.join(dist, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${entries}
</urlset>
`,
);

const robots =
  siteConfig.env === 'production'
    ? `User-agent: *
Allow: /
Disallow: /api/

Sitemap: ${url('/sitemap.xml')}
`
    : `# ${siteConfig.env} build — not for indexing
User-agent: *
Disallow: /
`;
writeFileSync(path.join(dist, 'robots.txt'), robots);
console.log(`✔ sitemap.xml (${routes.filter((r) => !r.noindex).length} URLs) and robots.txt (${siteConfig.env})`);
