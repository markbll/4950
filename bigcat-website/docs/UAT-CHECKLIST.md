# UAT checklist

Run on **staging** before any production decision, and again on production immediately after cutover.

- **Automated:** `BASE_URL=https://<host> BASIC_AUTH=user:pass MAIL_LOG_DIR=<optional> node scripts/uat.mjs` → `test-results/uat-report.json`
- **Manual:** the items marked 👤 below

## Pre-release results (build environment, 26 Sep 2026)

Run against the **real Nginx site rules** (`deploy/nginx/bigcat-site.conf`, `nginx -t` OK on 1.24) serving a staging build, with the PHP API behind it (PHP 8.4; mail `log` transport). Only difference from the server: `/api` was proxied to `php -S` because PHP-FPM wasn't available, so **FastCGI wiring still needs checking on the real server**.

| Area | Result |
|---|---|
| Routes: direct load + raw HTML content (39 routes) | 82/82 ✅ |
| SEO: sitemap (39 URLs), robots, noindex on staging | 42/42 ✅ |
| Cache headers (HTML no-cache, assets immutable) | 40/40 ✅ |
| Security headers on every page, API headers, no stack traces | 42/42 ✅ |
| API hardening (405, 415, missing header, foreign Origin, token, bot timing, internal paths 404) | 12/12 ✅ |
| Validation (client + server) | 4/4 ✅ |
| Anti-spam (honeypot accepted silently + sends no email, rate limit 429) | 3/3 ✅ |
| Tier tagging (Box Hill → melbourne, Geelong → regional_vic, Perth → remote) | 3/3 ✅ |
| Forms end-to-end (check-up, contact, subscribe; lead email with tier + Reply-To) | 8/8 ✅ |
| Console errors (every route + form flows) | 41/41 ✅ |
| Accessibility: axe-core WCAG 2.0/2.1/2.2 A+AA on all routes, skip link | 40/40 ✅ |
| Analytics events + UTM + no PII in dataLayer | 49/49 ✅ |
| Lazy Google Map | ✅ |
| Mobile (menu toggle, Escape, click-to-call, persistent CTA) | 5/5 ✅ |
| Reflow at 320 px (≈400% zoom), all routes | 39/39 ✅ |
| **Total** | **411/411 ✅** |

Also passing: `npm run lint`, 80 Vitest tests, 91 PHP tests, `npm run verify` build gate.

**Not verified here, must be done on the server:** HTTPS/certificates, PHP-FPM FastCGI, real SMTP delivery, basic auth, a live website fetch in the check-up (outbound HTTP was blocked here, so only the "could not connect" path ran end-to-end; the HTML analysis is covered by PHP tests), GA4 receiving events, Lighthouse on real hosting.

## Checklist

### Routes and rendering
- [ ] Every route in `sitemap.xml` loads directly (typed URL) and on refresh — *automated*
- [ ] View-source shows full prerendered content, title, description, canonical, OG, JSON-LD — *automated*; 👤 spot-check 5 pages
- [ ] `/x/` and `/x/index.html` 301 to `/x`; legacy URLs 301 per `redirects.map` — *automated (sample)*; 👤 test every final legacy URL
- [ ] Unknown URL returns the 404 page with status 404 and `noindex` — *automated*
- [ ] 👤 Internal links: click through nav, footer, cards; `npm run verify` checks every internal href at build time

### Devices and layout
- [ ] 👤 iPhone Safari and Android Chrome: header, click-to-call, menu, forms, sticky header
- [ ] 👤 Desktop Chrome, Safari, Firefox, Edge
- [ ] No horizontal scroll at 320 px — *automated*; 👤 browser zoom 200% on desktop, text usable
- [ ] 👤 No layout shift on load (fonts preloaded, fixed-ratio image placeholders)

### Forms
- [ ] Check-up: 3 steps, errors, back/next, results with 8 categories, "Reviewed by our team" wording, no score — *automated*; 👤 with a real website on the server
- [ ] Contact: validation, `?meeting=in_person|video` preselect, success — *automated*
- [ ] Subscribe: consent required, success — *automated*
- [ ] 👤 Lead emails arrive in the team inbox with tier tag, Reply-To = submitter, readable formatting
- [ ] Honeypot and rate limiting — *automated*
- [ ] 👤 Consent wording approved (Spam Act 2003)

### Tier tagging
- [ ] melbourne / regional_vic / remote — *automated + unit tests (shared fixtures)*; 👤 try 5 real client suburbs

### Analytics
- [ ] page_view, package_view, location_page_view(region), checkup_start, checkup_complete, lead_submit(tier), contact_submit, consultation_click(in_person|video), email_click, directions_click, cta_click, UTM — *automated*
- [ ] phone_click — 👤 once `business.phone` is set
- [ ] No personal information in events — *automated*
- [ ] 👤 GA4 DebugView receives events on production

### SEO and structured data
- [ ] Unique titles/descriptions, canonicals — *verify + tests*
- [ ] 👤 Rich Results Test + validator.schema.org: home, a package, a service, a location with FAQs
- [ ] NAP identical on every page — *verify*
- [ ] Staging: noindex meta + `X-Robots-Tag` + robots `Disallow: /`; production: indexable, sitemap in robots — *automated (per env)*

### Accessibility
- [ ] axe WCAG 2.2 AA — *automated*
- [ ] 👤 Keyboard only: every link/button reachable, visible focus, menu opens/closes, forms usable, error summary focus
- [ ] 👤 Screen reader (VoiceOver or NVDA): headings, landmarks, form labels and errors, check-up step changes announced
- [ ] 👤 Reduced motion respected

### Performance
- [ ] 👤 Lighthouse mobile on staging: aim for Performance ≥ 90, LCP < 2.5 s, CLS < 0.1
- [ ] Hashed assets immutable, HTML no-cache — *automated*
- [ ] 👤 gzip/brotli active

### Security and server
- [ ] Security headers on HTML, assets and API — *automated*
- [ ] 👤 HTTPS valid (staging hostname without underscore), HTTP→HTTPS, www→apex
- [ ] `/api/health.php` all true — *automated*
- [ ] 👤 PHP error log clean after UAT; no warnings
- [ ] 👤 FTP credential rotated

### Content sign-off
- [ ] 👤 Every **REVIEW** field in [content-inventory.md](content-inventory.md) approved by someone with local knowledge
- [ ] 👤 `npm run check:facts` → no required TODOs; no `[TODO: …]` markers on the production build
- [ ] 👤 Placeholder images/logo replaced; privacy + terms legal review

### Sign-off

| Role | Name | Date | Signature |
|---|---|---|---|
| Business owner | | | |
| Reviewer (local content) | | | |
| Technical | | | |
| **Production go-live approval** | | | |
