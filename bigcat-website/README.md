# Big Cat Marketing — website (2026 local marketing rebuild)

Melbourne's local marketing team for small business. Every public route is
**prerendered to static HTML** at build time, with its own title, meta
description, canonical, Open Graph, JSON-LD and full body content. React only
loads for the interactive "islands" (the check-up, contact and subscribe forms).
Forms post to a small, dependency-free **PHP API**.

| | |
|---|---|
| Production | https://bigcatmarketing.com.au/ — **do not change until UAT sign-off + explicit approval** |
| Staging | `ai_website.bigcatmarketing.com.au` — see the [staging hostname warning](#staging-hostname-warning) |
| Stack | React 19 + TypeScript + Vite 7 (SSR prerender), PHP 8.2+ API, Nginx |

> **Security:** the FTP credential shared earlier is compromised. **Rotate it
> before any production deploy**, and use SFTP/SSH keys if the host supports
> them. No secrets are stored in this repository; see [`.env.example`](.env.example).

---

## Contents

1. [Quick start](#quick-start)
2. [Project structure](#project-structure)
3. [How it works](#how-it-works)
4. [Environment variables](#environment-variables)
5. [Deploying to staging](#deploying-to-staging)
6. [PHP API deployment](#php-api-deployment)
7. [Nginx routing and cache rules](#nginx-routing-and-cache-rules)
8. [Rollback](#rollback)
9. [Production cutover](#production-cutover)
10. [Search Console](#search-console)
11. [Updating GBP and citations to the new URLs](#updating-google-business-profile-and-citations)
12. [Editing content and business facts](#editing-content-and-business-facts)
13. [Deliverables index](#deliverables-index)

---

## Quick start

Requirements: Node 20.19+ (22 LTS recommended), PHP 8.2+ with `curl`, `dom`, `mbstring`.

```bash
npm install
npm run lint        # ESLint (incl. jsx-a11y) + TypeScript
npm run test        # Vitest (routes, SEO, schema, tiers, validation, forms) + PHP tests
npm run build       # client build → SSR build → prerender → sitemap/robots → verify
```

Local development:

```bash
cp .env.example .env            # then set VITE_SITE_ENV=development
npm run dev:api                 # PHP API on :8000 (needs the API env vars exported — see below)
npm run dev                     # Vite dev server with SSR; /api proxied to :8000
npm run preview                 # serve dist/ exactly like Nginx does (after a build)
```

To run the API locally with the mail **log** transport (writes `.eml` files instead of sending):

```bash
APP_ENV=development APP_SECRET=$(openssl rand -hex 32) STORAGE_DIR=/tmp/bigcat \
MAIL_TRANSPORT=log MAIL_TO=team@example.com MAIL_FROM=web@example.com \
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:4173 npm run dev:api
```

### npm scripts

| Script | What it does |
|---|---|
| `dev` | Vite dev server; pages are server-rendered with the same code as the prerender |
| `dev:api` | PHP built-in server for `api/` (development only) |
| `build` | `build:client` → `build:ssr` → `prerender` → `sitemap` → `verify` |
| `prerender` | Writes `dist/<route>/index.html` for all 39 routes + `dist/404.html` |
| `sitemap` | Writes `dist/sitemap.xml` and an environment-aware `dist/robots.txt` |
| `verify` | Build quality gate: titles, descriptions, canonicals, one H1, content length, JSON-LD, FAQPage rules, NAP identical on every page, no broken internal links, noindex on non-production, secret scan |
| `preview` | Local server that mimics the Nginx rules (clean URLs, 404, redirects, headers, cache) |
| `lint` / `test` | See above |
| `check:facts` | Lists business facts still TODO in `src/data/business.ts` |
| `docs:generate` | Regenerates `docs/seo-metadata-map.md` and `docs/content-inventory.md` |

Automated UAT (Playwright + axe-core; see [docs/UAT-CHECKLIST.md](docs/UAT-CHECKLIST.md)):

```bash
BASE_URL=https://<staging-host> BASIC_AUTH=user:pass node scripts/uat.mjs
```

---

## Project structure

```
bigcat-website/
├── src/
│   ├── data/            business.ts (single source of NAP), packages, services,
│   │                    industries, locations, caseStudies
│   ├── routes.ts        route registry: every public URL + title/description
│   ├── seo/             head tags + JSON-LD (generated from business.ts)
│   ├── components/      Layout (header/footer/NAP), blocks, map, islands wrapper
│   ├── pages/           page templates (home, packages, services, industries, locations, misc)
│   ├── islands/         interactive React forms (hydrated on the client)
│   ├── client/          tiny client scripts: menu, lazy map, analytics, island hydration
│   ├── lib/             tier tagging, validation, analytics (PII-safe)
│   ├── entry-server.tsx renderPage() used by dev + prerender
│   └── entry-client.ts  client entry
├── api/                 PHP endpoints (contact, checkup, subscribe, health, token) + lib/ + tests/
├── shared/              data shared by TS and PHP (Melbourne localities, tier fixtures)
├── scripts/             prerender, sitemap, verify, preview, uat, docs, check-facts
├── deploy/nginx/        Nginx server blocks, shared site rules, security headers, redirects.map
├── public/              favicon, placeholder logo + share image (TODO: replace)
└── docs/                deployment, UAT, security, rollback, redirects, SEO map, content inventory, package scope, citation register
```

---

## How it works

- **Prerendering.** `src/entry-server.tsx` renders a full HTML document per route. `scripts/prerender.mjs` writes one static file per route using the Vite manifest for hashed assets. View-source on any page shows the full content.
- **Islands.** Only elements marked `data-island` hydrate. React (≈66 KB gz) is loaded on demand; the page entry script is ≈5 KB gz. The footer subscribe form hydrates when scrolled near or focused.
- **Single source of NAP.** `src/data/business.ts` feeds the footer NAP block, the contact page, meta and JSON-LD. `npm run verify` fails if the NAP text differs on any page. Missing facts are `null` with `TODO(fact)` comments and show visible `[TODO: …]` markers on non-production builds.
- **Production safety gate.** With `VITE_SITE_ENV=production` the build **fails** while required facts (phone, email) are still TODO.
- **Indexing.** Non-production builds are `noindex, nofollow`, robots.txt disallows everything, and Nginx adds `X-Robots-Tag` on staging.
- **Lead tiers.** `melbourne` / `regional_vic` / `remote` from suburb + state, using `shared/greater-melbourne-localities.json` in both TypeScript and PHP (shared fixtures keep them in sync).
- **Check-up honesty.** Website checks run server-side on the prospect's public home page. Google Business Profile, Map Pack and Reviews are always "Reviewed by our team within 1 business day". No score is ever calculated or shown.

---

## Environment variables

See [`.env.example`](.env.example) for every variable with comments. Summary:

| Variable | Where | Purpose |
|---|---|---|
| `VITE_SITE_URL` | build | Canonical origin (keep as production for both environments) |
| `VITE_SITE_ENV` | build | `staging` or `production` (indexing, TODO markers, fact gate) |
| `VITE_GA_MEASUREMENT_ID` | build | Optional GA4 ID (public) |
| `APP_ENV` | API | `production` / `staging` / `development` |
| `APP_SECRET` | API | ≥32 random chars — signs form tokens, hashes IPs |
| `ALLOWED_ORIGINS` | API | Origins allowed to POST (CSRF check) |
| `STORAGE_DIR` | API | Writable dir **outside** the web root |
| `MAIL_*`, `SMTP_*` | API | Lead delivery (SMTP recommended) |
| `CHECKUP_FETCH_ENABLED` | API | Turn automatic website checks on/off |
| `TRUSTED_PROXY_HEADER` | API | Only behind a trusted CDN/proxy |

API variables are read from the process environment (PHP-FPM `env[...]` or hosting panel) or from the file in `BIGCAT_ENV_FILE`, which must be outside the web root (the API refuses an env file inside it).

---

## Deploying to staging

Full step-by-step instructions: **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)**. In short:

```bash
npm ci && npm run lint && npm run test
VITE_SITE_ENV=staging VITE_SITE_URL=https://bigcatmarketing.com.au npm run build
```

Upload as a new release (SFTP/rsync preferred; FTP only over TLS with the **rotated** credential):

```
<release>/dist/   ← contents of dist/ (the web root)
<release>/api/    ← api/ WITHOUT api/tests/ and api/dev-router.php
private/bigcat.env, private/storage/   ← created once, outside the web root
```

Then check `https://<staging-host>/api/health.php` returns `"ok": true` and run the UAT.

### Staging hostname warning

`ai_website` contains an **underscore**. Public certificate authorities (including Let's Encrypt) do not issue certificates for hostnames with underscores, so **HTTPS cannot work on `ai_website.bigcatmarketing.com.au`**. Use `ai-website.bigcatmarketing.com.au` (hyphen) or `staging.bigcatmarketing.com.au`. The Nginx config uses `ai-website`. Keep staging behind HTTP basic auth.

---

## PHP API deployment

- PHP **8.2+** with `curl`, `dom`/`xml`, `mbstring`, `json`, `openssl`. No Composer, no database.
- Only five endpoints are public: `contact.php`, `checkup.php`, `subscribe.php`, `health.php`, `token.php`. Nginx returns 404 for everything else under `/api/` (including `lib/` and `tests/`); `.htaccess` files do the same on Apache.
- `api/lib/greater-melbourne-localities.json` must be deployed (it is a committed copy of `shared/…`; a PHP test fails if they drift).
- Create `STORAGE_DIR` (0700, owned by the PHP-FPM user) outside the web root.
- Configure SMTP with an account on the business's own domain, with SPF/DKIM for that sender. Test with `MAIL_TRANSPORT=log` on staging first if needed (it is refused when `APP_ENV=production`).
- Visit `/api/health.php` — all checks must be `true`.

| Endpoint | Method | Notes |
|---|---|---|
| `/api/token.php` | GET | Signed form token (min age 2 s, max 2 h) |
| `/api/contact.php` | POST JSON | Enquiry → team email; returns `{ tier }` |
| `/api/checkup.php` | POST JSON | Check-up lead + SSRF-safe website checks; returns categories |
| `/api/subscribe.php` | POST JSON | Newsletter opt-in with express consent |
| `/api/health.php` | GET | Config health (booleans only) |

Every POST requires `Content-Type: application/json`, `X-Requested-With: fetch`, an allowed `Origin`, a valid `X-Form-Token`, and passes a honeypot and per-IP rate limit.

---

## Nginx routing and cache rules

Config files: [`deploy/nginx/`](deploy/nginx) — `bigcat.conf` (server blocks), `bigcat-site.conf` (shared rules), `bigcat-security-headers.conf`, `redirects.map`. The config passes `nginx -t` on Nginx 1.24.

| Request | Behaviour |
|---|---|
| `/packages` | serves `dist/packages/index.html` (no redirect) |
| `/packages/` or `/packages/index.html` | 301 → `/packages` |
| legacy URL in `redirects.map` | 301 → new URL |
| unknown URL | `dist/404.html` with status 404 (noindex) |
| `/assets/*` (hashed) | `Cache-Control: public, max-age=31536000, immutable` |
| HTML pages | `Cache-Control: no-cache` (always revalidated — deploys show immediately) |
| images / fonts outside `/assets` | 1 day |
| `sitemap.xml`, `robots.txt` | 1 hour |
| `/api/*.php` (5 endpoints) | FastCGI to PHP-FPM; responses `no-store` |
| dotfiles | 404 (except `/.well-known/`) |

Security headers on every response: CSP (no inline scripts except one hashed boot line; no inline styles), HSTS, `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`, COOP. If `INLINE_BOOT` in `src/entry-server.tsx` ever changes, update the hash in `bigcat-security-headers.conf` (the build prints it).

---

## Rollback

See **[docs/ROLLBACK.md](docs/ROLLBACK.md)**. Releases are immutable folders; rollback is re-pointing the `current` symlink (or re-uploading the previous release zip on FTP-only hosting) and reloading PHP-FPM. HTML is `no-cache`, so rollback is visible immediately; hashed assets from both releases can coexist.

---

## Production cutover

Only after the UAT checklist is signed off **and** explicit written approval. Detailed runbook in [docs/DEPLOYMENT.md § Production cutover](docs/DEPLOYMENT.md#production-cutover). Summary:

1. Rotate the compromised FTP credential; confirm no old credentials remain.
2. Fill every required fact in `business.ts` (`npm run check:facts` exits 0); replace placeholder logo/images; legal review of privacy + terms; approve location/industry copy.
3. Crawl the current site and finalise `redirects.map` (every legacy URL with traffic/backlinks → closest new page).
4. `VITE_SITE_ENV=production npm run build`; deploy to the production release path with production env vars (`APP_ENV=production`, `ALLOWED_ORIGINS=https://bigcatmarketing.com.au`).
5. Enable the production server block, reload Nginx, smoke-test, run `scripts/uat.mjs` with `EXPECT_NOINDEX=0 SKIP_RATE_LIMIT=1`.
6. Search Console + GBP + citations updates (below). Monitor 404s and Search Console for four weeks.

---

## Search Console

1. Verify the **Domain property** `bigcatmarketing.com.au` (DNS TXT) so http/https/www are all covered.
2. Keep staging out of the index: basic auth + `noindex` + `robots.txt Disallow` (do not add staging as an indexed property).
3. After cutover, submit `https://bigcatmarketing.com.au/sitemap.xml`.
4. URL-inspect and request indexing for `/`, `/packages`, `/locations/melbourne` and the top service pages.
5. Use **Pages → Not found (404)** weekly for the first month; add missing legacy URLs to `redirects.map`.
6. Validate structured data in the Rich Results Test and Schema.org validator for a sample of each page type (home, package, service, location with FAQs).
7. Link GA4 (if enabled) and mark `lead_submit`, `contact_submit` and `phone_click` as key events.

---

## Updating Google Business Profile and citations

1. Update the GBP **website** field to `https://bigcatmarketing.com.au/` (add UTM if desired: `?utm_source=google&utm_medium=organic&utm_campaign=gbp`).
2. Make GBP name, phone, service areas and hours **exactly** match `src/data/business.ts`. Keep the address hidden unless `address.isPublic` is approved.
3. Set GBP services to match `/services/*`; link the appointment URL to `/contact` or `/local-visibility-checkup`.
4. Work through [`docs/citation-register-template.csv`](docs/citation-register-template.csv): update each directory's website URL to the new canonical page and correct any NAP mismatch. Record dates and status.
5. Update social profile links (Facebook, Instagram, LinkedIn), email signatures and any paid ads' final URLs to new paths.
6. Add the GBP URL and social URLs to `business.ts` so they appear in `sameAs`.

---

## Editing content and business facts

- **Business facts**: `src/data/business.ts` only. Then rebuild. `npm run check:facts` shows what is outstanding.
- **Locations / industries**: each entry has `reviewStatus` and `needsReview`. Once reviewed by someone with local knowledge, set `reviewStatus: 'approved'` and clear `needsReview`. Keep copy unique (a test fails if two location pages are too similar). No individual suburb pages.
- **Case studies**: add to `src/data/caseStudies.ts` only with written client approval and a source for every figure. The Proof section appears automatically.
- **Packages**: `src/data/packages.ts` (prices ex GST; never promise rankings, Map Pack positions or lead numbers).
- Run `npm run docs:generate` after content changes to refresh the SEO map and content inventory.

---

## Deliverables index

| # | Deliverable | Location |
|---|---|---|
| 1 | Source tree | this folder |
| 2 | README | this file |
| 3 | `.env.example` | [`.env.example`](.env.example) |
| 4 | Build / deploy instructions | [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) |
| 5 | Redirect map | [deploy/nginx/redirects.map](deploy/nginx/redirects.map), [docs/REDIRECTS.md](docs/REDIRECTS.md) |
| 6 | SEO metadata map | [docs/seo-metadata-map.md](docs/seo-metadata-map.md) (generated) |
| 7 | Sitemap generator | [scripts/sitemap.mjs](scripts/sitemap.mjs) |
| 8 | UAT checklist | [docs/UAT-CHECKLIST.md](docs/UAT-CHECKLIST.md), [scripts/uat.mjs](scripts/uat.mjs) |
| 9 | Content inventory | [docs/content-inventory.md](docs/content-inventory.md) (generated) |
| 10 | Package scope | [docs/PACKAGE-SCOPE.md](docs/PACKAGE-SCOPE.md) |
| 11 | Security checklist | [docs/SECURITY-CHECKLIST.md](docs/SECURITY-CHECKLIST.md) |
| 12 | Rollback procedure | [docs/ROLLBACK.md](docs/ROLLBACK.md) |
| 13 | Citation register template | [docs/citation-register-template.csv](docs/citation-register-template.csv) |
