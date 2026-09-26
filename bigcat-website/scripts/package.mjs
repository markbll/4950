/**
 * Assemble the FTP upload folder from a finished build:
 *   release/ftp/            ← upload the CONTENTS of this folder to the site root
 *     (dist/ contents)      static site + generated .htaccess
 *     api/                  PHP endpoints (no tests/, no dev-router.php)
 *     _private/.htaccess    deny-all; bigcat.env goes here (never generated from the repo)
 * and a zip of it in release/ (keep it — it is your rollback copy).
 *
 * If BIGCAT_ENV_CONTENT is set (CI only, from repository secrets), it is written to
 * release/ftp/_private/bigcat.env. Locally, upload your env file by hand or with
 * scripts/deploy-ftp.sh.
 */
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { dist, root } from './lib.mjs';

if (!existsSync(path.join(dist, 'index.html')) || !existsSync(path.join(dist, '.htaccess'))) {
  console.error('Build first: npm run build');
  process.exit(1);
}
const env = /Disallow: \/\s*$/m.test(readFileSync(path.join(dist, 'robots.txt'), 'utf8')) ? 'staging' : 'production';
const out = path.join(root, 'release', 'ftp');
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

cpSync(dist, out, { recursive: true, filter: (src) => !/[\\/]\.vite([\\/]|$)|\.csp-inline-hash\.txt$/.test(src) });
cpSync(path.join(root, 'api'), path.join(out, 'api'), {
  recursive: true,
  filter: (src) => !/[\\/]api[\\/]tests([\\/]|$)|dev-router\.php$/.test(src),
});
const lock = readFileSync(path.join(root, 'deploy', 'private-template', '.htaccess'));
mkdirSync(path.join(out, '_private', 'storage'), { recursive: true });
writeFileSync(path.join(out, '_private', '.htaccess'), lock);
writeFileSync(path.join(out, '_private', 'storage', '.htaccess'), lock);
if (process.env.BIGCAT_ENV_CONTENT) {
  writeFileSync(path.join(out, '_private', 'bigcat.env'), process.env.BIGCAT_ENV_CONTENT.trim() + '\n', { mode: 0o600 });
  console.log('  wrote _private/bigcat.env from BIGCAT_ENV_CONTENT');
}

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
const zip = path.join(root, 'release', `bigcat-${env}-${stamp}.zip`);
try {
  execFileSync('zip', ['-qr', zip, '.', '-x', '_private/bigcat.env'], { cwd: out });
  console.log(`✔ release/ftp/ ready (${env} build) + ${path.relative(root, zip)}`);
} catch {
  console.log(`✔ release/ftp/ ready (${env} build) — zip not available, upload the folder`);
}
