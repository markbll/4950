# Rollback procedure

Releases are immutable folders under `releases/<timestamp>`; `current` is a symlink. HTML is served `no-cache`, so a rollback is visible to visitors on their next request. Hashed assets never collide between releases.

## When to roll back

- Home page, packages, contact or check-up broken for real users
- Forms not delivering leads (and not fixable within ~30 minutes)
- `api/health.php` not `ok` after deploy
- Widespread 404s or redirect loops, or pages indexed/de-indexed unexpectedly

## Staging or production (SSH hosting)

```bash
ssh deploy@host
cd /var/www/bigcat/<env>
ls -1t releases | head          # newest first; pick the last known-good release
ln -sfn /var/www/bigcat/<env>/releases/<GOOD_TIMESTAMP> current
sudo systemctl reload php8.3-fpm
curl -s https://<host>/api/health.php
```

Confirm: home page loads, view-source shows the expected content, one test form submission arrives.

## FTP-only hosting

1. Rename the live web-root folder (e.g. `public_html` → `public_html_failed`) — or, if renaming is impossible, upload the previous release zip's `dist/` and `api/` over the top.
2. Upload/restore the previous release (`bigcat-<GOOD>.zip`) to `public_html`.
3. Re-check the API env vars in the hosting panel still match.

## First production cutover (back to the old site)

Before cutover, the old site must be backed up and restorable.

1. Disable the new production server block (or restore the previous Nginx vhost file) and `nginx -t && systemctl reload nginx`; **or** point DNS back to the old host (TTL was lowered to 300 s).
2. Restore the old site's files from the backup if they were replaced.
3. In Google Business Profile and citations, revert the website URL only if the old URLs no longer resolve.
4. Record what failed; fix on staging; repeat UAT before retrying.

## Afterwards

- Keep the failed release folder for diagnosis; delete releases older than the last 5 good ones.
- Note the rollback in the change log with the time, reason and who approved it.
