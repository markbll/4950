/**
 * Renders public/og-default.png (1200×630 social share image) from the real
 * vector logo in public/brand/. Re-run after changing the logo or tagline:
 *   node scripts/generate-brand-images.mjs
 * favicon.svg / apple-touch-icon.png / logo.png are built from the same artwork.
 */
import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { root } from './lib.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright-core');
const logo = readFileSync(path.join(root, 'public', 'brand', 'logo-reverse.svg'), 'utf8');
const CHROMIUM = process.env.CHROMIUM_PATH || (existsSync('/opt/pw-browsers/chromium-1194/chrome-linux/chrome') ? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' : undefined);

const browser = await chromium.launch({ executablePath: CHROMIUM });
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
await page.setContent(`<!doctype html><html><body style="margin:0">
<div style="width:1200px;height:630px;box-sizing:border-box;padding:72px 80px;display:flex;align-items:center;gap:72px;
  background:radial-gradient(900px 420px at 95% 0%,rgba(247,147,29,.28),transparent 60%),#0A0E1A;color:#fff;font-family:Arial,Helvetica,sans-serif">
  <div style="width:360px;flex:none">${logo.replace('<svg ', '<svg style="width:100%;height:auto" ')}</div>
  <div>
    <div style="font-size:64px;font-weight:700;line-height:1.05">Get found by the customers near you.</div>
    <div style="margin-top:28px;font-size:28px;line-height:1.35;color:#E5E7EB">Online, in print and across your community.</div>
    <div style="margin-top:28px;font-size:24px;font-weight:700;color:#F7931D">Melbourne-based · Working with small businesses across Australia</div>
  </div>
</div></body></html>`);
await page.screenshot({ path: path.join(root, 'public', 'og-default.png') });
await browser.close();
console.log('✔ public/og-default.png');
