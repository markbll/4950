/**
 * Automated UAT run (complements the manual checklist in docs/UAT-CHECKLIST.md).
 *
 *   BASE_URL=https://ai-website.bigcatmarketing.com.au \
 *   BASIC_AUTH=user:pass EXPECT_NOINDEX=1 MAIL_LOG_DIR=... node scripts/uat.mjs
 *
 * Checks every route (direct load, raw HTML content, headers, cache), redirects,
 * 404, sitemap/robots, API hardening, forms end-to-end, tier tagging, analytics
 * events (and absence of personal information), mobile layout/reflow, console
 * errors and axe-core WCAG 2.2 AA rules. Writes test-results/uat-report.json.
 */
import { mkdirSync, readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { root } from './lib.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright-core');
const axeSource = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');

const BASE = (process.env.BASE_URL || 'http://localhost:4173').replace(/\/$/, '');
const EXPECT_NOINDEX = process.env.EXPECT_NOINDEX !== '0';
const MAIL_LOG_DIR = process.env.MAIL_LOG_DIR || '';
const AUTH = process.env.BASIC_AUTH ? { Authorization: `Basic ${Buffer.from(process.env.BASIC_AUTH).toString('base64')}` } : {};
const SKIP_RATE_LIMIT = process.env.SKIP_RATE_LIMIT === '1';
const CHROMIUM = process.env.CHROMIUM_PATH || (existsSync('/opt/pw-browsers/chromium-1194/chrome-linux/chrome') ? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' : undefined);

const results = [];
const record = (area, name, ok, detail = '') => {
  results.push({ area, name, ok, detail });
  if (!ok) console.log(`  ✖ [${area}] ${name}${detail ? ` — ${detail}` : ''}`);
};
const get = (p, opts = {}) => fetch(BASE + p, { redirect: 'manual', ...opts, headers: { ...AUTH, ...(opts.headers || {}) } });

// ---------- HTTP-level checks ----------
console.log(`UAT against ${BASE}`);
const sitemapRes = await get('/sitemap.xml');
record('seo', 'sitemap.xml 200', sitemapRes.status === 200);
const sitemap = await sitemapRes.text();
const paths = [...sitemap.matchAll(/<loc>https?:\/\/[^/<]+([^<]*)<\/loc>/g)].map((m) => m[1] || '/');
record('seo', 'sitemap lists 39 routes', paths.length === 39, `found ${paths.length}`);
const robots = await (await get('/robots.txt')).text();
record('seo', 'robots.txt matches environment', EXPECT_NOINDEX ? /Disallow: \/\s*$/m.test(robots) : /Sitemap:/.test(robots));

const REQUIRED_HEADERS = ['content-security-policy', 'x-content-type-options', 'referrer-policy', 'permissions-policy', 'x-frame-options'];
for (const p of paths) {
  const res = await get(p);
  const html = await res.text();
  const h = res.headers;
  const ok = res.status === 200 && /text\/html/.test(h.get('content-type') || '');
  record('routes', `${p} direct load 200`, ok, `status ${res.status}`);
  record('routes', `${p} raw HTML has prerendered content`, /<h1[\s>]/.test(html) && /<main/.test(html) && html.length > 8000 && /application\/ld\+json/.test(html));
  record('cache', `${p} HTML not long-cached`, /no-cache/.test(h.get('cache-control') || ''), h.get('cache-control') || 'missing');
  const missing = REQUIRED_HEADERS.filter((k) => !h.get(k));
  record('security', `${p} security headers`, missing.length === 0, missing.join(', '));
  if (EXPECT_NOINDEX) record('seo', `${p} noindex (meta + header)`, /noindex/.test(h.get('x-robots-tag') || '') && /name="robots" content="noindex/.test(html));
}

const slash = await get('/packages/');
record('routes', 'trailing slash 301 → no slash', slash.status === 301 && /\/packages$/.test(slash.headers.get('location') || ''));
const idx = await get('/about/index.html');
record('routes', '/index.html 301 → clean URL', idx.status === 301);
const legacy = await get('/about-us');
record('routes', 'legacy redirect /about-us → /about', legacy.status === 301 && /\/about$/.test(legacy.headers.get('location') || ''));
const nf = await get('/definitely-not-a-page');
const nfHtml = await nf.text();
record('routes', 'unknown URL → 404 page', nf.status === 404 && /could not find that page/.test(nfHtml) && /noindex/.test(nfHtml));
const dot = await get('/.csp-inline-hash.txt');
record('security', 'dotfiles not served', dot.status === 404);

const home = await (await get('/')).text();
const asset = home.match(/src="(\/assets\/[^"]+\.js)"/)?.[1];
if (asset) {
  const a = await get(asset);
  record('cache', 'hashed assets immutable', /immutable/.test(a.headers.get('cache-control') || '') && /max-age=31536000/.test(a.headers.get('cache-control') || ''));
}

// ---------- API hardening ----------
const health = await get('/api/health.php');
const healthJson = await health.json().catch(() => ({}));
record('api', 'health 200 + all checks true', health.status === 200 && healthJson.ok === true, JSON.stringify(healthJson.checks || healthJson));
for (const p of ['/api/lib/config.php', '/api/lib/mailer.php', '/api/tests/run.php', '/api/dev-router.php', '/api/lib/greater-melbourne-localities.json']) {
  const r = await get(p);
  record('api', `${p} not reachable`, r.status === 404 || r.status === 403, `status ${r.status}`);
}
const tokenJson = await (await get('/api/token.php')).json();
const origin = new URL(BASE).origin;
const post = (p, body, headers = {}) =>
  get(p, { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body), headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'fetch', Origin: origin, 'X-Form-Token': tokenJson.token, ...headers } });
record('api', 'GET on form endpoint → 405', (await get('/api/contact.php')).status === 405);
record('api', 'non-JSON content type → 415', (await post('/api/contact.php', 'a=b', { 'Content-Type': 'application/x-www-form-urlencoded' })).status === 415);
record('api', 'missing X-Requested-With → 403', (await post('/api/contact.php', {}, { 'X-Requested-With': '' })).status === 403);
record('api', 'foreign Origin → 403 (CSRF)', (await post('/api/contact.php', {}, { Origin: 'https://evil.example' })).status === 403);
record('api', 'missing form token → 403', (await post('/api/contact.php', {}, { 'X-Form-Token': '' })).status === 403);
const tooFresh = await (await get('/api/token.php')).json();
record('api', 'token used instantly (bot timing) → 403', (await post('/api/subscribe.php', { email: 'a@example.com', consent: true }, { 'X-Form-Token': tooFresh.token })).status === 403);
await new Promise((r) => setTimeout(r, 2500));
const inval = await post('/api/contact.php', { name: '', email: 'bad', suburb: '', state: 'XX', message: '' });
const invalJson = await inval.json();
record('validation', 'server-side validation → 422 with field errors', inval.status === 422 && ['name', 'email', 'suburb', 'message'].every((k) => invalJson.errors?.[k]));
const apiHeaders = inval.headers;
record('security', 'API responses no-store + nosniff', /no-store/.test(apiHeaders.get('cache-control') || '') && apiHeaders.get('x-content-type-options') === 'nosniff');
record('security', 'no stack traces in API errors', !/(Stack trace|\.php:\d+|Fatal error)/i.test(JSON.stringify(invalJson)));

const mailCount = () => (!MAIL_LOG_DIR ? -1 : existsSync(MAIL_LOG_DIR) ? readdirSync(MAIL_LOG_DIR).filter((f) => f.endsWith('.eml')).length : 0);
const before = mailCount();
const bot = await post('/api/contact.php', { name: 'Bot', email: 'bot@example.com', suburb: 'Coburg', state: 'VIC', message: 'spam', company_fax: 'x' });
record('anti-spam', 'honeypot submission accepted silently', bot.status === 200);
if (before >= 0) record('anti-spam', 'honeypot submission sends no email', mailCount() === before);

for (const [suburb, state, tier] of [['Geelong', 'VIC', 'regional_vic'], ['Perth', 'WA', 'remote'], ['Box Hill', 'VIC', 'melbourne']]) {
  const r = await post('/api/contact.php', { name: 'UAT Tester', email: 'uat@example.com', suburb, state, message: `Tier test ${suburb}` });
  const j = await r.json();
  record('tier', `${suburb} ${state} → ${tier}`, r.status === 200 && j.data?.tier === tier, JSON.stringify(j));
}
if (MAIL_LOG_DIR) {
  const eml = readdirSync(MAIL_LOG_DIR)
    .filter((f) => f.endsWith('.eml'))
    .map((f) => readFileSync(path.join(MAIL_LOG_DIR, f), 'utf8'))
    .find((e) => e.includes('Tier test Box Hill')) ?? '';
  record('forms', 'lead email contains tier tag', /tier: melbourne/.test(eml));
  record('forms', 'lead email Reply-To is the enquirer', /Reply-To: <uat@example.com>/.test(eml));
}

// ---------- Browser checks ----------
const browser = await chromium.launch({ executablePath: CHROMIUM });
const ctxOpts = { extraHTTPHeaders: AUTH, serviceWorkers: 'block' };

async function openPage(context, p) {
  const page = await context.newPage();
  const errors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('requestfailed', (r) => {
    if (r.url().startsWith(origin)) errors.push(`request failed: ${r.url()}`);
  });
  const res = await page.goto(BASE + p, { waitUntil: 'networkidle' });
  return { page, errors, res };
}

const desktop = await browser.newContext({ ...ctxOpts, viewport: { width: 1366, height: 900 } });
const axeTotals = {};
for (const p of paths) {
  const { page, errors } = await openPage(desktop, p);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(150);
  record('console', `${p} no console errors`, errors.length === 0, errors.join(' | '));
  await page.evaluate(axeSource); // CDP evaluate is not blocked by the page CSP (addScriptTag would be)
  const axe = await page.evaluate(async () => {
    const r = await axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'] } });
    return r.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, target: v.nodes[0]?.target?.join(' ') }));
  });
  for (const v of axe) axeTotals[v.id] = (axeTotals[v.id] || 0) + v.nodes;
  record('a11y', `${p} axe WCAG 2.2 AA`, axe.length === 0, axe.map((v) => `${v.id}(${v.impact}) ×${v.nodes} e.g. ${v.target}`).join('; '));
  const dl = await page.evaluate(() => JSON.stringify(window.dataLayer || []));
  record('analytics', `${p} page_view fired`, dl.includes('"event":"page_view"'));
  await page.close();
}

// Keyboard: skip link is first focusable and visible on focus
{
  const { page } = await openPage(desktop, '/');
  await page.keyboard.press('Tab');
  const skip = await page.evaluate(() => ({ text: document.activeElement?.textContent, top: document.activeElement?.getBoundingClientRect().top }));
  record('a11y', 'skip link first in tab order and visible', skip.text === 'Skip to main content' && skip.top >= 0);
  await page.close();
}

// Analytics events
{
  const { page } = await openPage(desktop, '/packages/gold?utm_source=uat&utm_medium=test&utm_campaign=launch');
  const dl = await page.evaluate(() => window.dataLayer);
  record('analytics', 'package_view with package slug', dl.some((e) => e.event === 'package_view' && e.package === 'gold'));
  record('analytics', 'UTM captured on events', dl.some((e) => e.event === 'page_view' && e.utm_source === 'uat' && e.utm_campaign === 'launch'));
  await page.close();
}
{
  const { page } = await openPage(desktop, '/locations/melbourne/northern-suburbs');
  const dl = await page.evaluate(() => window.dataLayer);
  record('analytics', 'location_page_view with region slug', dl.some((e) => e.event === 'location_page_view' && e.region === 'northern-suburbs' && e.tier === 'melbourne'));
  await page.evaluate(() => document.addEventListener('click', (e) => e.preventDefault(), { capture: true }));
  await page.click('a[data-consultation="video"]');
  await page.click('a[data-cta^="checkup_"] >> nth=0');
  const dl2 = await page.evaluate(() => window.dataLayer);
  record('analytics', 'consultation_click (video)', dl2.some((e) => e.event === 'consultation_click' && e.mode === 'video'));
  record('analytics', 'cta_click', dl2.some((e) => e.event === 'cta_click' && String(e.cta).startsWith('checkup_')));
  await page.close();
}
{
  const { page } = await openPage(desktop, '/contact');
  await page.evaluate(() => document.addEventListener('click', (e) => e.preventDefault(), { capture: true }));
  await page.click('a[data-track="directions_click"]');
  const dl = await page.evaluate(() => window.dataLayer);
  record('analytics', 'directions_click', dl.some((e) => e.event === 'directions_click'));
  const hasTel = await page.$('a[href^="tel:"]');
  if (hasTel) {
    await hasTel.click();
    record('analytics', 'phone_click', (await page.evaluate(() => window.dataLayer)).some((e) => e.event === 'phone_click'));
  } else record('analytics', 'phone_click (skipped — no phone in business.ts yet)', true, 'TODO: re-run once phone is set');
  await page.evaluate(() => document.querySelector('#map-heading')?.scrollIntoView());
  await page.waitForTimeout(600);
  record('maps', 'Google Map lazy-loads on /contact', (await page.$('.map-embed iframe[src*="google.com/maps"]')) !== null);
  await page.close();
}

// Forms end-to-end
{
  const { page, errors } = await openPage(desktop, '/local-visibility-checkup');
  await page.waitForTimeout(2200); // token min age
  await page.click('button:has-text("Next")');
  record('validation', 'check-up: empty step shows error summary', await page.isVisible('.error-summary'));
  await page.fill('#chk-businessName', 'UAT Plumbing');
  await page.fill('#chk-website', 'example.com');
  await page.fill('#chk-suburb', 'Coburg');
  await page.selectOption('#chk-industry', 'trades');
  await page.click('button:has-text("Next")');
  await page.fill('#chk-mainServiceArea', 'Northern suburbs');
  await page.fill('#chk-primaryService', 'Emergency plumbing');
  await page.click('button:has-text("Next")');
  await page.fill('#chk-contactName', 'Uat Person');
  await page.fill('#chk-email', 'uat.person@example.com');
  await page.fill('#chk-phone', '0412 345 678');
  await page.click('button:has-text("Get my check-up")');
  record('validation', 'check-up: consent required', await page.isVisible('#chk-consent-error'));
  await page.check('#chk-consent');
  await page.click('button:has-text("Get my check-up")');
  await page.waitForSelector('.checkup-results', { timeout: 30000 }).catch(() => null);
  const cats = await page.$$eval('.result h3', (els) => els.map((e) => e.textContent));
  record('forms', 'check-up end-to-end shows 8 result categories', cats.length === 8, cats.join(', '));
  const bodyText = await page.textContent('.checkup-results').catch(() => '');
  record('forms', 'check-up shows no invented score', !/\b\d{1,3}\s*(\/\s*100|%|out of)/i.test(bodyText || ''));
  record('forms', 'check-up tier message (Melbourne)', /Greater Melbourne/.test(bodyText || ''));
  const dl = await page.evaluate(() => window.dataLayer);
  record('analytics', 'checkup_start / checkup_complete / lead_submit(tier)', ['checkup_start', 'checkup_complete'].every((ev) => dl.some((e) => e.event === ev)) && dl.some((e) => e.event === 'lead_submit' && e.tier === 'melbourne'));
  const dlText = JSON.stringify(dl);
  record('analytics', 'no personal information in dataLayer', !/uat\.person@example\.com|0412 ?345 ?678|Uat Person|UAT Plumbing/.test(dlText));
  record('console', 'check-up flow no console errors', errors.length === 0, errors.join(' | '));
  await page.close();
}
{
  const { page, errors } = await openPage(desktop, '/contact?meeting=in_person');
  await page.waitForTimeout(2200);
  record('forms', 'contact: ?meeting=in_person preselects', await page.isChecked('#contact-meeting-in_person'));
  await page.click('form[aria-label="Contact Big Cat Marketing"] button[type="submit"]');
  record('validation', 'contact: client validation errors', (await page.$$('.error-text')).length >= 3);
  await page.fill('#contact-name', 'Sam Tester');
  await page.fill('#contact-email', 'sam@example.com');
  await page.fill('#contact-phone', '03 9123 4567');
  await page.fill('#contact-suburb', 'Footscray');
  await page.fill('#contact-message', 'UAT contact message');
  await page.click('form[aria-label="Contact Big Cat Marketing"] button[type="submit"]');
  await page.waitForSelector('.form-success', { timeout: 15000 }).catch(() => null);
  record('forms', 'contact end-to-end success', await page.isVisible('.form-success'));
  const dl = await page.evaluate(() => window.dataLayer);
  record('analytics', 'contact_submit with tier', dl.some((e) => e.event === 'contact_submit' && e.tier === 'melbourne'));
  record('console', 'contact flow no console errors', errors.length === 0, errors.join(' | '));
  await page.close();
}
{
  const { page } = await openPage(desktop, '/about');
  await page.waitForTimeout(2200);
  await page.focus('#sub-email');
  await page.waitForTimeout(500);
  await page.fill('#sub-email', 'subscriber@example.com');
  await page.check('#sub-consent');
  await page.click('.subscribe-form button[type="submit"]');
  await page.waitForSelector('.footer-subscribe .form-success', { timeout: 15000 }).catch(() => null);
  record('forms', 'subscribe end-to-end success', await page.isVisible('.footer-subscribe .form-success'));
  await page.close();
}

// Mobile + reflow
const mobile = await browser.newContext({ ...ctxOpts, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
{
  const { page } = await openPage(mobile, '/');
  record('mobile', 'nav collapsed behind Menu button', (await page.isVisible('.menu-toggle')) && !(await page.isVisible('#site-nav')));
  await page.click('.menu-toggle');
  record('mobile', 'Menu opens nav (aria-expanded=true)', (await page.isVisible('#site-nav')) && (await page.getAttribute('.menu-toggle', 'aria-expanded')) === 'true');
  await page.keyboard.press('Escape');
  record('mobile', 'Escape closes nav', !(await page.isVisible('#site-nav')));
  record('mobile', 'header click-to-call visible', await page.isVisible('.header-call'));
  record('mobile', 'persistent check-up CTA visible', await page.isVisible('.header-cta'));
  await page.close();
}
const narrow = await browser.newContext({ ...ctxOpts, viewport: { width: 320, height: 640 } });
for (const p of paths) {
  const page = await narrow.newPage();
  await page.goto(BASE + p, { waitUntil: 'load' });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  record('reflow', `${p} no horizontal scroll at 320px (≈400% zoom)`, overflow <= 1, `overflow ${overflow}px`);
  await page.close();
}

// Rate limiting (last — it exhausts the bucket for this IP)
if (!SKIP_RATE_LIMIT) {
  let got429 = false;
  for (let i = 0; i < 120 && !got429; i++) {
    const r = await post('/api/subscribe.php', { email: `rl${i}@example.com`, consent: true });
    if (r.status === 429) got429 = true;
  }
  record('anti-spam', 'rate limiting returns 429', got429);
}

await browser.close();

const failed = results.filter((r) => !r.ok);
const byArea = {};
for (const r of results) {
  byArea[r.area] ??= { pass: 0, fail: 0 };
  byArea[r.area][r.ok ? 'pass' : 'fail']++;
}
mkdirSync(path.join(root, 'test-results'), { recursive: true });
writeFileSync(path.join(root, 'test-results', 'uat-report.json'), JSON.stringify({ base: BASE, date: new Date().toISOString(), byArea, axeTotals, results }, null, 2));
console.log('\nUAT summary by area:');
for (const [a, c] of Object.entries(byArea)) console.log(`  ${a.padEnd(11)} ${c.pass} passed, ${c.fail} failed`);
console.log(`\n${failed.length ? '✖' : '✔'} ${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
