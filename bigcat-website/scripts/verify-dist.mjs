/**
 * Post-build quality gate. Fails the build if any prerendered page is missing
 * content or metadata, links are broken, NAP differs between pages, or
 * structured data is malformed.
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { dist, loadServer, outFile } from './lib.mjs';

const { routes, siteConfig, business, fullTitle } = await loadServer();
const errors = [];
const warn = [];
const fail = (msg) => errors.push(msg);

const routePaths = new Set(routes.map((r) => r.path));
const titles = new Map();
const descriptions = new Map();
let napReference = null;

const decode = (s) =>
  s
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
const text = (html) => decode(html.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
const attr = (html, re) => {
  const m = html.match(re);
  return m ? decode(m[1]) : null;
};

function walkTypes(node, out = []) {
  if (Array.isArray(node)) node.forEach((n) => walkTypes(n, out));
  else if (node && typeof node === 'object') {
    if (node['@type']) out.push(...[].concat(node['@type']));
    Object.values(node).forEach((v) => walkTypes(v, out));
  }
  return out;
}

for (const route of routes) {
  const file = outFile(route.path);
  if (!existsSync(file)) {
    fail(`${route.path}: missing ${path.relative(dist, file)}`);
    continue;
  }
  const html = readFileSync(file, 'utf8');
  const where = route.path;

  const title = attr(html, /<title>([^<]*)<\/title>/);
  if (!title) fail(`${where}: missing <title>`);
  else {
    if (title !== fullTitle(route)) fail(`${where}: title mismatch`);
    if (titles.has(title)) fail(`${where}: duplicate title with ${titles.get(title)}`);
    titles.set(title, where);
    if (title.length > 75) warn.push(`${where}: long title (${title.length} chars)`);
  }
  const desc = attr(html, /<meta name="description" content="([^"]*)"/);
  if (!desc) fail(`${where}: missing meta description`);
  else {
    if (descriptions.has(desc)) fail(`${where}: duplicate description with ${descriptions.get(desc)}`);
    descriptions.set(desc, where);
    if (desc.length > 170) warn.push(`${where}: long description (${desc.length} chars)`);
  }
  const canonical = attr(html, /<link rel="canonical" href="([^"]*)"/);
  const expected = `${siteConfig.siteUrl}${route.path}`;
  if (canonical !== expected) fail(`${where}: canonical ${canonical} !== ${expected}`);
  if (!/<meta property="og:title"/.test(html) || !/<meta property="og:image"/.test(html)) fail(`${where}: missing Open Graph tags`);

  const robots = attr(html, /<meta name="robots" content="([^"]*)"/);
  if (siteConfig.env !== 'production' && !/noindex/.test(robots ?? '')) fail(`${where}: non-production build must be noindex`);
  if (siteConfig.env === 'production' && /noindex/.test(robots ?? '')) fail(`${where}: production page is noindex`);

  const h1s = html.match(/<h1[\s>]/g) ?? [];
  if (h1s.length !== 1) fail(`${where}: expected exactly one <h1>, found ${h1s.length}`);

  const main = html.match(/<main[^>]*>([\s\S]*?)<\/main>/);
  const mainText = main ? text(main[1]) : '';
  if (mainText.length < 400) fail(`${where}: main content looks too thin (${mainText.length} chars) — prerender may have failed`);
  if (/\bundefined\b|\[object Object\]|\bNaN\b/.test(mainText)) fail(`${where}: suspicious text (undefined/NaN/[object Object]) in main content`);

  // JSON-LD
  const ld = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  if (!ld) fail(`${where}: missing JSON-LD`);
  else {
    try {
      const data = JSON.parse(ld[1]);
      const types = walkTypes(data);
      for (const t of ['WebSite', 'BreadcrumbList', 'ProfessionalService', 'Organization']) {
        if (!types.includes(t)) fail(`${where}: JSON-LD missing ${t}`);
      }
      const hasFaqMarkup = /<details class="faq"/.test(html);
      if (hasFaqMarkup !== types.includes('FAQPage')) fail(`${where}: FAQPage schema must exist only where FAQs are shown`);
      if (route.kind === 'service' && !types.includes('Service')) fail(`${where}: Service schema missing`);
      if (route.kind === 'package' && !types.includes('Offer')) fail(`${where}: Offer schema missing`);
      if (!business.address.isPublic && types.includes('PostalAddress')) fail(`${where}: address published while isPublic=false`);
    } catch (e) {
      fail(`${where}: JSON-LD does not parse (${e.message})`);
    }
  }

  // NAP consistency — text of the footer NAP block must be identical on every page.
  const footer = html.match(/<footer[\s\S]*?<div class="nap" data-nap="">([\s\S]*?)<\/div>/);
  if (!footer) fail(`${where}: footer NAP block missing`);
  else {
    const nap = text(footer[1]);
    if (napReference === null) napReference = nap;
    else if (nap !== napReference) fail(`${where}: footer NAP differs from other pages`);
  }
  const allNaps = [...html.matchAll(/<div class="nap" data-nap="">([\s\S]*?)<\/div>/g)].map((m) => text(m[1]));
  if (new Set(allNaps).size > 1) fail(`${where}: NAP blocks on this page differ from each other`);
  if (!html.includes(business.serviceAreaLine.replace(/&/g, '&amp;'))) fail(`${where}: service-area line missing`);

  // Internal links
  for (const m of html.matchAll(/href="(\/[^"#?]*)(?:[?#][^"]*)?"/g)) {
    const href = m[1];
    if (href === '/' || routePaths.has(href)) continue;
    if (href.startsWith('/api/')) continue;
    const onDisk = path.join(dist, href);
    if (existsSync(onDisk) && statSync(onDisk).isFile()) continue;
    fail(`${where}: broken internal link ${href}`);
  }
}

// 404 page
const nf = path.join(dist, '404.html');
if (!existsSync(nf)) fail('404.html missing');
else if (!/noindex/.test(readFileSync(nf, 'utf8'))) fail('404.html must be noindex');

// Sitemap + robots
const sitemapFile = path.join(dist, 'sitemap.xml');
if (!existsSync(sitemapFile)) fail('sitemap.xml missing');
else {
  const sm = readFileSync(sitemapFile, 'utf8');
  for (const r of routes) if (!sm.includes(`<loc>${siteConfig.siteUrl}${r.path}</loc>`)) fail(`sitemap missing ${r.path}`);
}
const robotsFile = path.join(dist, 'robots.txt');
if (!existsSync(robotsFile)) fail('robots.txt missing');
else if (siteConfig.env !== 'production' && !/Disallow: \/\s*$/m.test(readFileSync(robotsFile, 'utf8'))) fail('non-production robots.txt must disallow all');

// Secrets scan over the whole dist tree
const SECRET_PATTERNS = [/SMTP_PASS/i, /APP_SECRET\s*=/, /-----BEGIN [A-Z ]*PRIVATE KEY-----/, /\bftp:\/\/[^\s"']+:[^\s"']+@/i, /AKIA[0-9A-Z]{16}/];
const walk = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((d) => (d.isDirectory() ? walk(path.join(dir, d.name)) : [path.join(dir, d.name)]));
for (const f of walk(dist)) {
  if (!/\.(html|js|css|txt|xml|json)$/.test(f)) continue;
  const c = readFileSync(f, 'utf8');
  for (const re of SECRET_PATTERNS) if (re.test(c)) fail(`possible secret in ${path.relative(dist, f)} (${re})`);
}

for (const w of warn) console.warn(`⚠ ${w}`);
if (errors.length) {
  console.error(`✖ verify failed with ${errors.length} error(s):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log(`✔ verify passed: ${routes.length} routes, unique titles/descriptions, canonicals, JSON-LD, NAP consistent, no broken internal links.`);
