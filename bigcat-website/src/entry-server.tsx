/**
 * Server entry — used by the dev server (vite.config.ts) and the build-time
 * prerender (scripts/prerender.mjs). Produces a complete HTML document per
 * route, so every public page is static HTML with its own metadata.
 */
import { renderToString } from 'react-dom/server';
import type { ReactNode } from 'react';
import { findRoute, notFoundRoute, routes, type RouteDef } from './routes';
import { headFor, renderHead } from './seo/head';
import { Layout } from './components/Layout';
import { RenderContext, type IslandName, type RenderCollector } from './components/Island';
import Home from './pages/Home';
import { PackageDetail, PackagesIndex } from './pages/Packages';
import { ServiceDetail, ServicesIndex } from './pages/Services';
import { IndustriesIndex, IndustryDetail } from './pages/Industries';
import { LocationDetail, LocationsIndex } from './pages/Locations';
import { About, Checkup, Contact, NotFound, Privacy, Results, Terms } from './pages/Misc';
import { getLocation } from './data/locations';
import { siteConfig } from './config';
import { business, outstandingFacts } from './data/business';

export { routes, notFoundRoute, siteConfig, business, outstandingFacts };
export { locations } from './data/locations';
export { industries } from './data/industries';
export { services } from './data/services';
export { packages } from './data/packages';
export { headFor } from './seo/head';
export { fullTitle } from './routes';

/** Inline boot snippet: marks JS as available before first paint (hash is allow-listed in the CSP). */
export const INLINE_BOOT = "document.documentElement.classList.add('js')";

function pageFor(route: RouteDef): ReactNode {
  switch (route.kind) {
    case 'home':
      return <Home />;
    case 'packages':
      return <PackagesIndex route={route} />;
    case 'package':
      return <PackageDetail route={route} />;
    case 'services':
      return <ServicesIndex route={route} />;
    case 'service':
      return <ServiceDetail route={route} />;
    case 'industries':
      return <IndustriesIndex route={route} />;
    case 'industry':
      return <IndustryDetail route={route} />;
    case 'locations':
      return <LocationsIndex route={route} />;
    case 'location':
      return <LocationDetail route={route} />;
    case 'checkup':
      return <Checkup route={route} />;
    case 'results':
      return <Results route={route} />;
    case 'about':
      return <About route={route} />;
    case 'contact':
      return <Contact route={route} />;
    case 'privacy':
      return <Privacy route={route} />;
    case 'terms':
      return <Terms route={route} />;
    default:
      return <NotFound />;
  }
}

export interface Assets {
  scripts: string[];
  styles: string[];
  /** Extra modulepreload hrefs per island, resolved by the caller from the Vite manifest. */
  preloads: string[];
  islandPreloads?: Partial<Record<IslandName, string[]>>;
  /** woff2 fonts to preload (above-the-fold faces only). */
  fonts?: string[];
}

export interface RenderedPage {
  html: string;
  status: number;
  route: RouteDef;
  islands: IslandName[];
}

function bodyAttrs(route: RouteDef): string {
  const attrs: Record<string, string> = { 'data-page-type': route.kind };
  if (route.kind === 'package' && route.slug) attrs['data-package'] = route.slug;
  if (route.kind === 'location' && route.slug) {
    attrs['data-region'] = route.slug;
    attrs['data-tier'] = getLocation(route.slug)?.tier ?? '';
  }
  if (route.kind === 'industry' && route.slug) attrs['data-industry'] = route.slug;
  return Object.entries(attrs)
    .map(([k, v]) => `${k}="${v}"`)
    .join(' ');
}

export async function renderPage(url: string, assets: Assets): Promise<RenderedPage> {
  const found = findRoute(url);
  const route = found ?? notFoundRoute;
  const collector: RenderCollector = { islands: new Set() };
  const body = renderToString(
    <RenderContext.Provider value={collector}>
      <Layout path={route.path}>{pageFor(route)}</Layout>
    </RenderContext.Provider>,
  );
  const head = renderHead(headFor(route), route);
  const islands = [...collector.islands];
  const preloads = new Set(assets.preloads);
  for (const name of islands) for (const p of assets.islandPreloads?.[name] ?? []) preloads.add(p);

  const html = `<!doctype html>
<html lang="en-AU">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script>${INLINE_BOOT}</script>
    ${head}
    <meta name="theme-color" content="#0A0E1A">
    <meta name="format-detection" content="telephone=no">
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    ${(assets.fonts ?? []).map((f) => `<link rel="preload" href="${f}" as="font" type="font/woff2" crossorigin>`).join('\n    ')}
    ${assets.styles.map((s) => `<link rel="stylesheet" href="${s}">`).join('\n    ')}
    ${[...preloads].map((p) => `<link rel="modulepreload" href="${p}">`).join('\n    ')}
    ${assets.scripts.map((s) => `<script type="module" src="${s}"></script>`).join('\n    ')}
  </head>
  <body ${bodyAttrs(route)}>
${body}
  </body>
</html>
`;
  return { html, status: found ? 200 : 404, route, islands };
}
