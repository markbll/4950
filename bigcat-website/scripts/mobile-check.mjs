/**
 * Mobile-friendliness check across 7 screen sizes (320px phone → tablet, incl. landscape).
 * For every page in sitemap.xml: no horizontal scroll, no text under 12px, tap targets ≥ 24px
 * (WCAG 2.2 AA), form fields ≥ 16px (prevents iOS zoom), sticky header ≤ 30% of the screen,
 * layout shift (CLS) ≤ 0.1, no JS errors. Also taps the mobile menu and the check-up form.
 *
 *   npm run preview            # in another terminal (or point BASE_URL at staging)
 *   BASE_URL=http://localhost:4173 npm run test:mobile
 */
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright-core');
const BASE = (process.env.BASE_URL || 'http://localhost:4173').replace(/\/$/, '');
const CHROMIUM = process.env.CHROMIUM_PATH || (existsSync('/opt/pw-browsers/chromium-1194/chrome-linux/chrome') ? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' : undefined);
const AUTH = process.env.BASIC_AUTH ? { Authorization: `Basic ${Buffer.from(process.env.BASIC_AUTH).toString('base64')}` } : {};
const b = await chromium.launch({ executablePath: CHROMIUM });
const sm = await (await fetch(BASE + '/sitemap.xml', { headers: AUTH })).text();
const paths = [...sm.matchAll(/<loc>https?:\/\/[^/<]+([^<]*)<\/loc>/g)].map((m) => m[1] || '/');
const devices = [
  ['small phone 320', 320, 640, 2],
  ['Galaxy 360', 360, 800, 3],
  ['iPhone SE 375', 375, 667, 2],
  ['iPhone 390', 390, 844, 3],
  ['Pro Max 430', 430, 932, 3],
  ['iPad mini 768', 768, 1024, 2],
  ['phone landscape 844x390', 844, 390, 3],
];
const issues = []; let checks = 0;
const add = (dev, p, msg) => issues.push(`[${dev}] ${p}: ${msg}`);
for (const [dev, w, h, dpr] of devices) {
  const ctx = await b.newContext({ extraHTTPHeaders: AUTH, viewport: { width: w, height: h }, deviceScaleFactor: dpr, isMobile: w < 800 || h < 500, hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1' });
  for (const p of paths) {
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', (e) => errs.push(e.message));
    await page.addInitScript(() => {
      window.__cls = 0;
      new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; }).observe({ type: 'layout-shift', buffered: true });
    });
    await page.goto(BASE + p, { waitUntil: 'networkidle' });
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(120);
    const r = await page.evaluate(() => {
      const vw = window.innerWidth, vh = window.innerHeight;
      const out = { overflow: document.documentElement.scrollWidth - vw, offenders: [], small: [], tapSmall: [], inputs: [], header: 0, viewport: '', cls: window.__cls };
      out.viewport = document.querySelector('meta[name=viewport]')?.content || '';
      const visible = (el) => { const s = getComputedStyle(el); const b = el.getBoundingClientRect(); return s.visibility !== 'hidden' && s.display !== 'none' && b.width > 0 && b.height > 0 && !el.closest('.hp,[aria-hidden=true],.visually-hidden'); };
      for (const el of document.querySelectorAll('body *')) {
        if (!visible(el)) continue;
        const b = el.getBoundingClientRect();
        if (b.right > vw + 1 && !el.closest('.table-wrap')) out.offenders.push(`${el.tagName.toLowerCase()}.${[...el.classList].join('.')} right=${Math.round(b.right)}`);
        const own = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
        if (own) { const fs = parseFloat(getComputedStyle(el).fontSize); if (fs < 12) out.small.push(`${el.tagName.toLowerCase()} ${fs}px "${el.textContent.trim().slice(0, 30)}"`); }
      }
      for (const el of document.querySelectorAll('a[href],button,input:not([type=hidden]),select,textarea,summary,[role=button]')) {
        if (!visible(el)) continue;
        const b = el.getBoundingClientRect();
        const inline = el.tagName === 'A' && el.closest('p,li,td,dd,label,.nap') && getComputedStyle(el).display === 'inline';
        if (!inline && (b.width < 24 || b.height < 24)) out.tapSmall.push(`${el.tagName.toLowerCase()} ${Math.round(b.width)}x${Math.round(b.height)} "${(el.textContent || el.getAttribute('aria-label') || el.name || '').trim().slice(0, 25)}"`);
      }
      for (const el of document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=hidden]),select,textarea')) {
        if (!visible(el)) continue; const fs = parseFloat(getComputedStyle(el).fontSize); if (fs < 16) out.inputs.push(`${el.name} ${fs}px`);
      }
      const hd = document.querySelector('.site-header'); out.header = hd ? hd.getBoundingClientRect().height / vh : 0;
      return out;
    });
    checks++;
    if (!/width=device-width/.test(r.viewport)) add(dev, p, 'viewport meta missing');
    if (r.overflow > 1) add(dev, p, `horizontal scroll ${r.overflow}px: ${r.offenders.slice(0, 3).join('; ')}`);
    if (r.small.length) add(dev, p, `text under 12px: ${r.small.slice(0, 3).join('; ')}`);
    if (r.tapSmall.length) add(dev, p, `tap targets under 24px: ${[...new Set(r.tapSmall)].slice(0, 4).join('; ')}`);
    if (r.inputs.length) add(dev, p, `inputs under 16px (iOS zoom): ${r.inputs.join(', ')}`);
    if (r.header > 0.3) add(dev, p, `sticky header uses ${Math.round(r.header * 100)}% of screen height`);
    if (r.cls > 0.1) add(dev, p, `layout shift CLS ${r.cls.toFixed(3)}`);
    if (errs.length) add(dev, p, `JS errors: ${errs.join(' | ')}`);
    await page.close();
  }
  // interactive checks on phones
  if (w < 1080) {
    const page = await ctx.newPage();
    await page.goto(BASE + '/', { waitUntil: 'networkidle' });
    const toggle = page.locator('.menu-toggle');
    if (await toggle.isVisible()) {
      await toggle.tap();
      const open = await page.isVisible('#site-nav');
      const links = await page.$$eval('#site-nav a', (as) => as.filter((a) => a.getBoundingClientRect().height >= 40).length);
      if (!open || links < 8) add(dev, '/', `menu open=${open}, links ≥40px tall: ${links}/8`);
      await toggle.tap();
      if (await page.isVisible('#site-nav')) add(dev, '/', 'menu did not close');
    }
    await page.goto(BASE + '/local-visibility-checkup', { waitUntil: 'networkidle' });
    await page.locator('#chk-businessName').tap();
    await page.locator('button:has-text("Next")').tap();
    if (!(await page.isVisible('.error-summary'))) add(dev, '/local-visibility-checkup', 'error summary not shown on tap');
    await page.close();
  }
  await ctx.close();
  console.log(`done ${dev}`);
}
await b.close();
console.log(`\n${checks} page×device checks, ${issues.length} issue(s)`);
for (const i of issues) console.log(' - ' + i);
process.exit(issues.length ? 1 : 0);
