#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Deploy a built release to cPanel/FTP hosting over FTPS (TLS required).
#
#   FTP_HOST=ftp.bigcatmarketing.com.au FTP_USER='website@bigcatmarketing.com.au' \
#     ./scripts/deploy-ftp.sh staging
#
# - The password is read from $FTP_PASS if set, otherwise prompted (hidden).
#   Never pass it as an argument, and never commit it.
# - Uploads dist/ to $FTP_REMOTE_DIR (default: / = the FTP account's root,
#   which for a cPanel subdomain account is usually the site's web root) and
#   api/ (without tests/dev-router) to $FTP_REMOTE_DIR/api.
# - Creates _private/ with a deny-all .htaccess. Uploads $ENV_FILE to
#   _private/bigcat.env if given (it is NEVER deleted or overwritten otherwise).
# - Backs up the current remote site to backups/<target>-<timestamp>/ first
#   (that folder is your rollback: ./scripts/deploy-ftp.sh rollback <folder>).
# - "production" requires CONFIRM_PRODUCTION=yes and a production build.
#
# Requires: lftp (macOS: brew install lftp · Ubuntu: sudo apt install lftp)
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
case "$TARGET" in
  staging|production|rollback) ;;
  *) echo "Usage: $0 staging|production|rollback <backup-folder>"; exit 2 ;;
esac

command -v lftp >/dev/null || { echo "lftp is required (brew install lftp / apt install lftp)"; exit 1; }
: "${FTP_HOST:?Set FTP_HOST}"
: "${FTP_USER:?Set FTP_USER}"
REMOTE="${FTP_REMOTE_DIR:-/}"
if [ -z "${FTP_PASS:-}" ]; then
  read -r -s -p "FTP password for $FTP_USER: " FTP_PASS; echo
fi
export LFTP_PASSWORD="$FTP_PASS"
unset FTP_PASS

LFTP_SETTINGS="set ftp:ssl-force true; set ftp:ssl-protect-data true; set ssl:verify-certificate ${FTP_VERIFY_CERT:-yes}; set net:max-retries 3; set net:timeout 30; set ftp:passive-mode true; set ftp:list-options -a"
# Host-managed files that must never be deleted or overwritten on the server:
# private config, ACME challenges, cgi-bin, PHP settings, the FTP quota file, local backups.
KEEP="--exclude-glob _private/ --exclude-glob .well-known/ --exclude-glob cgi-bin/ --exclude-glob .user.ini --exclude-glob .ftpquota --exclude-glob backups/"
run_lftp() { lftp --env-password -u "$FTP_USER" -e "$LFTP_SETTINGS; $1; bye" "$FTP_HOST"; }

if [ "$TARGET" = rollback ]; then
  SRC="${2:?Usage: $0 rollback backups/<folder>}"
  [ -d "$SRC" ] || { echo "No such backup folder: $SRC"; exit 1; }
  echo "Restoring $SRC → $FTP_HOST:$REMOTE (private config untouched)"
  run_lftp "mirror -R --delete $KEEP '$SRC' '$REMOTE'"
  echo "✔ Rolled back. Check /api/health.php and the home page."
  exit 0
fi

[ -f dist/index.html ] && [ -f dist/.htaccess ] || { echo "Build first: VITE_SITE_ENV=$TARGET npm run build"; exit 1; }
if grep -q "Disallow: /$" dist/robots.txt; then BUILD_ENV=nonprod; else BUILD_ENV=production; fi
if [ "$TARGET" = production ]; then
  [ "${CONFIRM_PRODUCTION:-}" = yes ] || { echo "Refusing: production needs CONFIRM_PRODUCTION=yes (after UAT sign-off + written approval)."; exit 1; }
  [ "$BUILD_ENV" = production ] || { echo "Refusing: dist/ is a non-production build."; exit 1; }
else
  [ "$BUILD_ENV" = nonprod ] || { echo "Refusing: dist/ is a production build; rebuild with VITE_SITE_ENV=staging."; exit 1; }
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="backups/$TARGET-$STAMP"
mkdir -p "$BACKUP"
echo "1/4 Backing up current remote site → $BACKUP"
run_lftp "mirror $KEEP '$REMOTE' '$BACKUP'" || echo "  (nothing to back up)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -a dist/. "$STAGE/"
rm -f "$STAGE/.csp-inline-hash.txt"
rm -rf "$STAGE/.vite"
mkdir -p "$STAGE/api"
cp -a api/. "$STAGE/api/"
rm -rf "$STAGE/api/tests" "$STAGE/api/dev-router.php"

echo "2/4 Uploading site + API → $FTP_HOST:$REMOTE"
run_lftp "mirror -R --delete $KEEP '$STAGE' '$REMOTE'"

echo "3/4 Ensuring locked _private/ folder"
PRIV="$(mktemp -d)"
cp deploy/private-template/.htaccess "$PRIV/.htaccess"
mkdir -p "$PRIV/storage"
cp deploy/private-template/.htaccess "$PRIV/storage/.htaccess"
CMDS="mkdir -p -f '$REMOTE/_private/storage'; put -O '$REMOTE/_private' '$PRIV/.htaccess'; put -O '$REMOTE/_private/storage' '$PRIV/storage/.htaccess'"
if [ -n "${ENV_FILE:-}" ]; then
  [ -f "$ENV_FILE" ] || { echo "ENV_FILE not found: $ENV_FILE"; exit 1; }
  CMDS="$CMDS; put -O '$REMOTE/_private' '$ENV_FILE' -o bigcat.env; chmod 600 '$REMOTE/_private/bigcat.env'"
  echo "  uploading $ENV_FILE → _private/bigcat.env"
fi
run_lftp "$CMDS"
rm -rf "$PRIV"

echo "4/4 Done. Backup kept in $BACKUP"
echo "Next: open https://<host>/api/health.php (all checks true), then run scripts/uat.mjs."
