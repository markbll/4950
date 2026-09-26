# Build and deployment

Nothing in this project deploys automatically. **Production is never deployed without UAT sign-off and explicit written approval.**

## 0. Before anything

- [ ] The previously shared FTP credential is **compromised**. Rotate it now. Prefer SFTP with SSH keys; if only FTP exists, use FTPS (explicit TLS) and a new, unique password stored in a password manager — never in this repo, chat or email.
- [ ] Confirm the host runs **PHP 8.2+** (with `curl`, `dom`, `mbstring`) and Nginx (Apache works via the included `.htaccess` files, but Nginx is the supported target).
- [ ] DNS + TLS for the staging host `website.bigcatmarketing.com.au` (cPanel: create the subdomain and run AutoSSL).

## Staging on cPanel / FTP — website.bigcatmarketing.com.au

This is the likely path for the current host (FTP account `website@bigcatmarketing.com.au`). Run it **from your own computer**: the build environment used to create this site cannot reach FTP.

**One-time setup in cPanel**

1. **Change the FTP password** (it was shared in plain text). cPanel → FTP Accounts → `website@…` → Change Password. Store the new one in a password manager only.
2. cPanel → Domains: create `website.bigcatmarketing.com.au`. Note its document root, and check that the FTP account's home directory **is** that document root.
3. cPanel → SSL/TLS Status → run AutoSSL for the subdomain (HTTPS must work before testing forms).
4. cPanel → MultiPHP Manager → set the subdomain to **PHP 8.2 or newer**. Check that the `curl`, `dom`/`xml` and `mbstring` extensions are enabled (Select PHP Version → Extensions).
5. cPanel → Directory Privacy → password-protect the subdomain folder (keeps staging private).
6. cPanel → Email Accounts: create a sending account (e.g. `website@bigcatmarketing.com.au` or `noreply@…`) for SMTP. Note its SMTP host/port from "Connect Devices".
7. If the subdomain folder already has an `.htaccess` with a PHP `AddHandler` block from MultiPHP, copy those lines into `deploy/apache/htaccess.local` (see `deploy/apache/README.md`).

**Create the staging config file** on your computer (never commit it), e.g. `~/bigcat-staging.env`:

```ini
APP_ENV=staging
APP_SECRET=<output of: openssl rand -hex 32>
ALLOWED_ORIGINS=https://website.bigcatmarketing.com.au
STORAGE_DIR=storage
MAIL_TRANSPORT=smtp
MAIL_TO=info@bigcatmarketing.com.au
MAIL_FROM=<the sending account>
MAIL_FROM_NAME=Big Cat Marketing Website
SMTP_HOST=<from cPanel, e.g. mail.bigcatmarketing.com.au>
SMTP_PORT=465
SMTP_SECURE=ssl
SMTP_USER=<the sending account>
SMTP_PASS=<its password>
CHECKUP_FETCH_ENABLED=1
# UAT only (the automated UAT makes more submissions than the normal limits allow). Remove after UAT.
RATE_LIMIT_SCALE=10
```

`STORAGE_DIR=storage` resolves to `_private/storage/`. If the FTP account can reach the folder **above** the web root, put the file in `../bigcat-private/bigcat.env` instead (preferred; the API looks there first).

**Build and deploy**

```bash
npm ci && npm run lint && npm test
VITE_SITE_ENV=staging npm run build
FTP_HOST=ftp.bigcatmarketing.com.au FTP_USER='website@bigcatmarketing.com.au' \
  ENV_FILE=~/bigcat-staging.env npm run deploy:staging      # prompts for the password
```

The script ([`scripts/deploy-ftp.sh`](../scripts/deploy-ftp.sh), needs `lftp`) does four things:

1. It backs up the current remote folder to `backups/staging-<time>/`.
2. It uploads over **FTPS** only (it refuses plain FTP), mirroring `dist/` plus `api/` and deleting stale files. It never touches `_private/`, `.well-known/`, `cgi-bin/` or `.user.ini`.
3. It creates `_private/` with a deny-all `.htaccess` and uploads your env file as `_private/bigcat.env` (mode 600).
4. It refuses to push a production build to staging, and refuses production at all unless `CONFIRM_PRODUCTION=yes`.

If the host's certificate doesn't match `ftp.bigcatmarketing.com.au`, try `FTP_HOST=bigcatmarketing.com.au`, or the server hostname cPanel shows under FTP Accounts → Configure FTP Client. Don't turn certificate checks off.

**Verify**

```bash
curl -u <user>:<pass> https://website.bigcatmarketing.com.au/api/health.php     # every check true
BASE_URL=https://website.bigcatmarketing.com.au BASIC_AUTH=<user>:<pass> SKIP_RATE_LIMIT=1 npm run uat
```

The UAT sends real test enquiries to `MAIL_TO`, so warn the inbox owner. Then work through the manual items in [UAT-CHECKLIST.md](UAT-CHECKLIST.md).

**Roll back:** `FTP_HOST=… FTP_USER=… ./scripts/deploy-ftp.sh rollback backups/staging-<time>`

This flow was tested end to end in the build environment against a local FTPS server and Apache 2.4. The `.htaccess` routing, the `_private/` env-file discovery with no server environment variables, and a rollback all worked, and the UAT passed 411/411.

## 1. Build (Nginx / VPS path)

```bash
npm ci
npm run lint
npm run test                    # Vitest + PHP tests
# Staging:
VITE_SITE_ENV=staging    VITE_SITE_URL=https://bigcatmarketing.com.au npm run build
# Production (fails while required business facts are TODO):
VITE_SITE_ENV=production VITE_SITE_URL=https://bigcatmarketing.com.au VITE_GA_MEASUREMENT_ID=G-XXXX npm run build
```

`npm run build` runs: TypeScript check → Vite client build → SSR build → prerender (39 routes + 404) → sitemap/robots → verify. It stops on any failure. Output:

- `dist/` — the web root (static HTML, hashed assets, sitemap, robots, images)
- `api/` — PHP endpoints (deploy **without** `api/tests/` and `api/dev-router.php`)

Package a release:

```bash
REL=$(date +%Y%m%d-%H%M%S)
mkdir -p release/$REL && cp -R dist release/$REL/dist
rsync -a --exclude tests --exclude dev-router.php api/ release/$REL/api/
(cd release && zip -qr bigcat-$REL.zip $REL)
```

Keep every release zip — it is your rollback.

## 2. Server layout (one-time)

```
/var/www/bigcat/staging/
├── releases/<timestamp>/{dist,api}
├── current -> releases/<timestamp>        # symlink switched on each deploy
└── private/                               # NOT web-accessible
    ├── bigcat.env                         # 0640, owner deploy, group php-fpm
    └── storage/                           # 0700, owner php-fpm user
```

`private/bigcat.env` holds the API variables from `.env.example` (APP_ENV, APP_SECRET, ALLOWED_ORIGINS, STORAGE_DIR, MAIL_*, SMTP_*). Nginx passes its path to PHP as `BIGCAT_ENV_FILE`. Alternatively set them as `env[...]` in the PHP-FPM pool.

Generate the secret with `openssl rand -hex 32`. Use a **different** secret for staging and production.

## 3. Nginx (one-time)

```bash
sudo cp deploy/nginx/bigcat-site.conf deploy/nginx/bigcat-security-headers.conf /etc/nginx/snippets/
sudo cp deploy/nginx/redirects.map /etc/nginx/snippets/bigcat-redirects.map
echo 'map $uri $bigcat_redirect { default ""; include /etc/nginx/snippets/bigcat-redirects.map; }' | sudo tee /etc/nginx/conf.d/bigcat-map.conf
sudo cp deploy/nginx/bigcat.conf /etc/nginx/sites-available/bigcat.conf
sudo htpasswd -c /etc/nginx/.htpasswd-bigcat-staging <reviewer>
# edit fastcgi_pass socket + certificate paths; COMMENT OUT the production server block until cutover
sudo ln -s /etc/nginx/sites-available/bigcat.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Certificates: `certbot certonly --webroot -w /var/www/letsencrypt -d website.bigcatmarketing.com.au`.

## 4. Deploy to staging

```bash
scp release/bigcat-$REL.zip deploy@host:/var/www/bigcat/staging/releases/
ssh deploy@host
cd /var/www/bigcat/staging/releases && unzip -q bigcat-$REL.zip && rm bigcat-$REL.zip
ln -sfn /var/www/bigcat/staging/releases/$REL /var/www/bigcat/staging/current
sudo systemctl reload php8.3-fpm     # clears OPcache for the new PHP files
```

**FTP-only hosting** (no SSH, no symlinks): upload `dist/*` to the web root (e.g. `public_html/`), `api/` to `public_html/api/` (without `tests/`), create `private/` **above** `public_html` for `bigcat.env` and `storage/`, and set the variables in the hosting panel. Upload to a new folder first and swap folder names to minimise the time the site is half-uploaded.

## 5. Verify staging

```bash
curl -s -u user:pass https://website.bigcatmarketing.com.au/api/health.php   # all checks true
BASE_URL=https://website.bigcatmarketing.com.au BASIC_AUTH=user:pass node scripts/uat.mjs
```

Then work through the manual items in [UAT-CHECKLIST.md](UAT-CHECKLIST.md).

## Production cutover

Pre-conditions (all required):

- [ ] UAT checklist signed off; **explicit written approval** to go live recorded.
- [ ] FTP credential rotated; old credentials revoked.
- [ ] `npm run check:facts` exits 0 (phone and email set; address public only if approved).
- [ ] Placeholder logo, favicon, share image and all "Image placeholder" blocks replaced.
- [ ] Location and industry copy reviewed (`reviewStatus: 'approved'`), privacy + terms legally reviewed.
- [ ] `redirects.map` finalised from a crawl of the current site (see [REDIRECTS.md](REDIRECTS.md)).
- [ ] Current production site fully backed up (files + any database) and the backup restore tested.

Steps:

1. Lower DNS TTL to 300 s a day ahead if DNS is changing.
2. Build with `VITE_SITE_ENV=production`. Confirm `dist/robots.txt` allows crawling and pages have `index, follow`.
3. Create `/var/www/bigcat/production/private/bigcat.env` with `APP_ENV=production`, a new `APP_SECRET`, `ALLOWED_ORIGINS=https://bigcatmarketing.com.au`, production SMTP and `MAIL_TRANSPORT=smtp`.
4. Deploy the release to `/var/www/bigcat/production/` exactly as for staging.
5. Enable the production server block (with `$bigcat_robots ""`), `nginx -t`, reload.
6. Smoke test: home, a package, a location, the 404, `/api/health.php`, one real contact form submission to the team inbox, one check-up.
7. Run `EXPECT_NOINDEX=0 SKIP_RATE_LIMIT=1 BASE_URL=https://bigcatmarketing.com.au node scripts/uat.mjs` (uses real SMTP — warn the team to expect test leads).
8. Search Console, GBP and citations — see README.
9. Monitor for 4 weeks: Search Console coverage + 404s, form deliveries, `error_log`, Core Web Vitals.

If anything fails, follow [ROLLBACK.md](ROLLBACK.md).
