import { absoluteUrl, business } from '../data/business';
import { isIndexable } from '../config';
import { fullTitle, type RouteDef } from '../routes';
import { buildGraph, jsonLdScript } from './schema';

export interface HeadData {
  title: string;
  description: string;
  canonical: string;
  robots: string;
  ogImage: string;
  jsonLd: unknown;
}

export const OG_IMAGE_PATH = '/og-default.png'; // TODO(asset): replace with approved branded share image (1200×630)

export function headFor(route: RouteDef): HeadData {
  const title = fullTitle(route);
  const indexable = isIndexable && !route.noindex;
  return {
    title,
    description: route.description,
    canonical: absoluteUrl(route.path),
    robots: indexable ? 'index, follow, max-image-preview:large' : 'noindex, nofollow',
    ogImage: absoluteUrl(OG_IMAGE_PATH),
    jsonLd: route.noindex ? null : buildGraph(route, title),
  };
}

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function renderHead(h: HeadData, route: RouteDef): string {
  const tags = [
    `<title>${esc(h.title)}</title>`,
    `<meta name="description" content="${esc(h.description)}">`,
    `<meta name="robots" content="${h.robots}">`,
    route.noindex ? '' : `<link rel="canonical" href="${esc(h.canonical)}">`,
    `<meta property="og:type" content="${route.kind === 'home' ? 'website' : 'article'}">`,
    `<meta property="og:site_name" content="${esc(business.name)}">`,
    `<meta property="og:locale" content="en_AU">`,
    `<meta property="og:title" content="${esc(h.title)}">`,
    `<meta property="og:description" content="${esc(h.description)}">`,
    `<meta property="og:url" content="${esc(h.canonical)}">`,
    `<meta property="og:image" content="${esc(h.ogImage)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta property="og:image:alt" content="${esc(`${business.name} — ${business.tagline}`)}">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${esc(h.title)}">`,
    `<meta name="twitter:description" content="${esc(h.description)}">`,
    `<meta name="twitter:image" content="${esc(h.ogImage)}">`,
    h.jsonLd ? `<script type="application/ld+json">${jsonLdScript(h.jsonLd)}</script>` : '',
  ];
  return tags.filter(Boolean).join('\n    ');
}
