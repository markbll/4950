/**
 * One-off helper: renders PLACEHOLDER brand images (logo.png, og-default.png,
 * apple-touch-icon.png) into public/ using Playwright's Chromium.
 * TODO(asset): replace all three with approved brand artwork before production.
 * Usage: node scripts/generate-placeholder-images.mjs  (needs playwright installed globally or locally)
 */
import { createRequire } from 'node:module';
import path from 'node:path';
import { root } from './lib.mjs';

const require = createRequire(import.meta.url);
let pw;
try {
  pw = require('playwright');
} catch {
  pw = require('/opt/node22/lib/node_modules/playwright');
}

const mark = `<svg viewBox="0 0 48 48" width="100%" height="100%"><rect width="48" height="48" rx="12" fill="#0A0E1A"/><path d="M12 34V16l7 6h10l7-6v18c0 3-3 6-6 6H18c-3 0-6-3-6-6z" fill="#F59E0B"/><circle cx="19.5" cy="28" r="2" fill="#0A0E1A"/><circle cx="28.5" cy="28" r="2" fill="#0A0E1A"/></svg>`;

const browser = await pw.chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage();

async function shot(file, w, h, html) {
  await page.setViewportSize({ width: w, height: h });
  await page.setContent(`<!doctype html><html><body style="margin:0">${html}</body></html>`);
  await page.screenshot({ path: path.join(root, 'public', file), omitBackground: false });
  console.log('wrote public/' + file);
}

await shot('logo.png', 512, 512, `<div style="width:512px;height:512px">${mark}</div>`);
await shot('apple-touch-icon.png', 180, 180, `<div style="width:180px;height:180px;background:#0A0E1A">${mark}</div>`);
await shot(
  'og-default.png',
  1200,
  630,
  `<div style="width:1200px;height:630px;box-sizing:border-box;padding:80px;background:radial-gradient(900px 400px at 90% 0%,rgba(245,158,11,.25),transparent 60%),#0A0E1A;color:#fff;font-family:Arial,Helvetica,sans-serif;display:flex;flex-direction:column;justify-content:space-between">
    <div style="display:flex;align-items:center;gap:24px"><div style="width:88px;height:88px">${mark}</div><div style="font-size:40px;font-weight:700">Big Cat Marketing</div></div>
    <div style="font-size:76px;font-weight:700;line-height:1.05;max-width:900px">Get found by the customers near you.</div>
    <div style="font-size:30px;color:#F59E0B;font-weight:700">Melbourne-based · Working with small businesses across Australia</div>
  </div>`,
);
await browser.close();
