# Legacy redirect map

File: [`deploy/nginx/redirects.map`](../deploy/nginx/redirects.map) — `map $uri $bigcat_redirect` in Nginx; also honoured by `npm run preview`.

> **Status: CANDIDATES ONLY.** The current production site could not be crawled when this map was drafted (network access to it was blocked from the build environment). Every line is a common legacy path, not a confirmed URL. It **must** be finalised before cutover.

## How to finalise

1. Export every URL the current site has, from all of:
   - the current `sitemap.xml` (and any `sitemap_index.xml`, `page-sitemap.xml`, `post-sitemap.xml`)
   - Search Console → Pages (indexed) and Performance → Pages (last 16 months)
   - Analytics landing pages (last 12 months)
   - a crawl (e.g. Screaming Frog) and backlink tools for linked URLs
2. For each URL choose the **closest** new page. Only use `/` if nothing is related. Avoid chains (old → old → new).
3. Blog/news posts with no equivalent: redirect to the closest service page, or keep a `/insights/...` section in a later phase — don't 404 URLs with backlinks.
4. Add lines as `/old-path   /new-path;` (exact match on the path, query strings ignored). Trailing-slash variants are handled automatically (`/x/` → `/x` first).
5. `sudo nginx -t && sudo systemctl reload nginx`, then test each with `curl -sI https://bigcatmarketing.com.au/old-path`.
6. After launch, check Search Console → Not found (404) weekly for a month and add anything missed.

## Candidate mappings

| Legacy path | New path |
|---|---|
| `/home`, `/index.php` | `/` |
| `/about-us` | `/about` |
| `/contact-us` | `/contact` |
| `/our-services` | `/services` |
| `/pricing`, `/plans` | `/packages` |
| `/seo`, `/local-seo` | `/services/local-seo` |
| `/google-my-business`, `/google-business-profile` | `/services/google-business-profile` |
| `/web-design`, `/website-design` | `/services/websites` |
| `/social-media-marketing` | `/services/social-media` |
| `/google-ads`, `/ppc` | `/services/local-ads` |
| `/email-marketing` | `/services/email-sms` |
| `/branding` | `/services/branding` |
| `/case-studies`, `/portfolio`, `/testimonials` | `/results` |
| `/privacy-policy` | `/privacy` |
| `/terms-and-conditions`, `/terms-of-use` | `/terms` |
| `/free-audit`, `/free-seo-audit` | `/local-visibility-checkup` |

Built-in canonical rules (not in the map): `/path/` → `/path`, `/path/index.html` → `/path`, `http` → `https`, `www` → apex.
