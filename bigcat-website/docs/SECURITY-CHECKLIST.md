# Security checklist

✅ = implemented and tested in this build · ☐ = must be done by the operator at deploy/cutover

## Secrets and access

- ☐ **Rotate the compromised FTP credential** before any production deploy; revoke the old one; prefer SFTP + SSH keys.
- ✅ No secrets in the repo. `.env*` is gitignored; only `.env.example` (blank values) is committed.
- ✅ `npm run verify` scans `dist/` for secret-like strings (SMTP password vars, private keys, AWS keys, credentialed FTP URLs).
- ✅ API reads secrets from the environment or an env file **outside** the web root (an env file inside the document root is refused).
- ☐ Separate `APP_SECRET` for staging and production (`openssl rand -hex 32`).
- ☐ SMTP account dedicated to the website, least privilege, strong unique password, stored in a password manager.
- ☐ Staging behind HTTP basic auth; reviewer passwords shared out-of-band.
- ☐ MFA on hosting panel, registrar, DNS, Google Business Profile, Search Console and GA.

## Transport and headers

- ✅ HTTP → HTTPS 301; HSTS (`max-age=31536000; includeSubDomains`).
- ✅ CSP: `default-src 'self'`, no inline script except one SHA-256-hashed boot line, **no inline styles**, `frame-ancestors 'none'`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`; only Google Tag Manager/Analytics and Google Maps (frame) allowed as third parties.
- ✅ `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` (camera, mic, geolocation, payment, usb off), COOP.
- ✅ `server_tokens off`; `X-Powered-By` removed by PHP.
- ✅ Dotfiles and build metadata not served; `/api/lib`, `/api/tests`, `dev-router.php` return 404 (Nginx) / denied (`.htaccess`).
- ☐ TLS certificate for a staging hostname **without an underscore** (CAs refuse underscores).

## Forms / API

- ✅ Strict method (405) and `Content-Type: application/json` (415).
- ✅ CSRF: JSON-only + required `X-Requested-With` header + `Origin`/`Referer` allow-list + signed, time-limited form token (HMAC-SHA256, 2 s minimum age, 2 h maximum).
- ✅ Honeypot field (bots get a silent success and nothing is sent).
- ✅ Per-IP sliding-window rate limits (contact 5 / subscribe 5 / check-up 4 per 15 min); `429` with `Retry-After`.
- ✅ Request body capped at 32 KB (PHP) / 64 KB (Nginx); JSON depth limited.
- ✅ Server-side validation of every field (lengths, enums, email, AU phone, URL); control characters stripped.
- ✅ Mail header injection prevented (CR/LF stripped from all headers; addresses validated). User addresses are only used as `Reply-To` — the forms cannot send mail to arbitrary recipients.
- ✅ No auto-reply to the submitter (prevents the site being used to spam third parties).
- ✅ Errors logged server-side without request bodies; clients get generic JSON messages; `display_errors` off; no stack traces.
- ✅ API responses: `Cache-Control: no-store`, `X-Robots-Tag: noindex`, restrictive CSP.
- ✅ `health.php` exposes booleans only (no versions, paths or hostnames).

## Check-up website fetch (SSRF)

- ✅ Only `http`/`https`, ports 80/443, no credentials in URL, `.local`/`.internal`/`localhost` rejected.
- ✅ DNS resolved server-side; **every** A/AAAA must be public (private, loopback, link-local incl. `169.254.169.254`, CGNAT, reserved, multicast, documentation, IPv4-mapped IPv6 blocked).
- ✅ Connection pinned to the vetted IP (`CURLOPT_RESOLVE`) — defeats DNS rebinding.
- ✅ Redirects followed manually (max 3), each hop re-validated.
- ✅ Timeouts (4 s connect, 8 s total per hop), 1.5 MB cap, `text/html` only, HTML parsed with network access disabled.
- ✅ `CHECKUP_FETCH_ENABLED=0` switches the fetch off entirely.

## Privacy and data retention

- ✅ No database; leads are emailed to the team, not stored on the web server.
- ✅ Rate-limit files store only an HMAC of the IP and timestamps; purged after 24 h.
- ✅ Mail `log` transport (UAT only) refused in production; its files are purged after 24 h.
- ✅ Analytics: parameter allow-list; values that look like emails/phones dropped; no names, emails or phones ever sent; GA loads only if an ID is configured; IP anonymisation flag set.
- ✅ Spam Act 2003: marketing consent is a separate, unticked, optional checkbox with clear wording; subscribe requires express consent; consent wording and time are recorded in the team email.
- ☐ Privacy policy and terms reviewed by a qualified adviser; list actual providers (host, SMTP, mailing platform).
- ☐ Team inbox retention period decided and applied.

## Supply chain and maintenance

- ✅ Minimal dependencies (runtime: React, React DOM, self-hosted fonts). PHP has no third-party code.
- ☐ `npm audit` before each release; keep PHP and Nginx patched.
- ☐ Review Nginx and PHP error logs weekly for the first month.

## Verified by

- `php api/tests/run.php` — 91 checks (SSRF, tokens, rate limits, validation, header injection, retention).
- `node scripts/uat.mjs` — headers, API hardening, CSRF/origin, honeypot, rate limiting, secrets not exposed (see `test-results/uat-report.json`).
