/**
 * Local production preview that mimics deploy/nginx/bigcat.conf:
 *  - /path → dist/path/index.html (clean URLs, no trailing slash; /path/ → 301 /path)
 *  - unknown → dist/404.html with status 404
 *  - /assets/* immutable caching, HTML no-cache
 *  - legacy redirects from deploy/nginx/redirects.map
 *  - /api/* proxied to PHP (`npm run dev:api`, default http://127.0.0.1:8000)
 *  - same security headers as Nginx
 * Usage: npm run preview  (PORT=4173 by default)
 */
import http from 'node:http';
import { createReadStream, existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { dist, root } from './lib.mjs';

const PORT = Number(process.env.PORT || 4173);
const API = new URL(process.env.DEV_API_PROXY || 'http://127.0.0.1:8000');
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.xml': 'application/xml; charset=utf-8', '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif',
  '.woff2': 'font/woff2', '.woff': 'font/woff', '.ico': 'image/x-icon',
};

const redirects = new Map();
const mapFile = path.join(root, 'deploy', 'nginx', 'redirects.map');
if (existsSync(mapFile)) {
  for (const line of readFileSync(mapFile, 'utf8').split('\n')) {
    const m = line.trim().match(/^([^#\s]\S*)\s+(\S+);$/);
    if (m) redirects.set(m[1], m[2]);
  }
}

const cspHashFile = path.join(dist, '.csp-inline-hash.txt');
const cspHash = existsSync(cspHashFile) ? readFileSync(cspHashFile, 'utf8').trim() : '';
const CSP = [
  "default-src 'self'",
  `script-src 'self' ${cspHash} https://www.googletagmanager.com`,
  "style-src 'self'",
  "img-src 'self' data: https://www.google-analytics.com https://www.googletagmanager.com",
  "font-src 'self'",
  "connect-src 'self' https://www.google-analytics.com https://*.google-analytics.com https://*.analytics.google.com https://www.googletagmanager.com",
  'frame-src https://www.google.com',
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
  'upgrade-insecure-requests',
].join('; ');

function securityHeaders(res) {
  res.setHeader('Content-Security-Policy', CSP);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=()');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  if (process.env.SITE_NOINDEX !== '0') res.setHeader('X-Robots-Tag', 'noindex, nofollow');
}

function send(res, file, status = 200) {
  const ext = path.extname(file);
  res.statusCode = status;
  res.setHeader('Content-Type', TYPES[ext] || 'application/octet-stream');
  res.setHeader('Cache-Control', file.includes(`${path.sep}assets${path.sep}`) ? 'public, max-age=31536000, immutable' : ext === '.html' ? 'no-cache' : 'public, max-age=3600');
  createReadStream(file).pipe(res);
}

http
  .createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    let p = decodeURIComponent(url.pathname);

    if (p.startsWith('/api/')) {
      const proxied = http.request(
        { hostname: API.hostname, port: API.port, path: req.url, method: req.method, headers: { ...req.headers, host: `${API.hostname}:${API.port}` } },
        (pr) => {
          res.writeHead(pr.statusCode || 502, pr.headers);
          pr.pipe(res);
        },
      );
      proxied.on('error', () => {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end('{"ok":false,"message":"API not running (npm run dev:api)"}');
      });
      req.pipe(proxied);
      return;
    }

    securityHeaders(res);
    if (p.includes('..') || p.includes('\0')) {
      res.statusCode = 400;
      return res.end();
    }
    if (redirects.has(p)) {
      res.writeHead(301, { Location: redirects.get(p) });
      return res.end();
    }
    if (p.length > 1 && p.endsWith('/')) {
      res.writeHead(301, { Location: p.replace(/\/+$/, '') + url.search });
      return res.end();
    }
    if (p.endsWith('/index.html')) {
      res.writeHead(301, { Location: p.slice(0, -'/index.html'.length) || '/' });
      return res.end();
    }
    const direct = path.join(dist, p);
    if (!path.basename(p).startsWith('.') && existsSync(direct) && statSync(direct).isFile()) return send(res, direct);
    const index = path.join(dist, p, 'index.html');
    if (existsSync(index)) return send(res, index);
    return send(res, path.join(dist, '404.html'), 404);
  })
  .listen(PORT, () => console.log(`Preview: http://localhost:${PORT}  (API proxied to ${API.origin})`));
