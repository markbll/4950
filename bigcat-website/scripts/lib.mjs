import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const dist = path.join(root, 'dist');
export const ssrEntry = path.join(root, 'dist-ssr', 'entry-server.js');

export async function loadServer() {
  if (!existsSync(ssrEntry)) {
    console.error('dist-ssr/entry-server.js not found. Run `npm run build:ssr` first.');
    process.exit(1);
  }
  return import(pathToFileURL(ssrEntry).href);
}

export function loadManifest() {
  const p = path.join(dist, '.vite', 'manifest.json');
  if (!existsSync(p)) {
    console.error('dist/.vite/manifest.json not found. Run `npm run build:client` first.');
    process.exit(1);
  }
  return JSON.parse(readFileSync(p, 'utf8'));
}

/** Output path for a route: '/' -> dist/index.html, '/a/b' -> dist/a/b/index.html */
export function outFile(routePath) {
  return routePath === '/' ? path.join(dist, 'index.html') : path.join(dist, ...routePath.slice(1).split('/'), 'index.html');
}
