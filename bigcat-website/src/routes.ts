/**
 * Route registry — the single list of public routes. Prerender, sitemap,
 * SEO metadata map and tests all read from here.
 */
import { packages } from './data/packages';
import { services } from './data/services';
import { industries } from './data/industries';
import { locations } from './data/locations';

export type PageKind =
  | 'home'
  | 'packages'
  | 'package'
  | 'services'
  | 'service'
  | 'industries'
  | 'industry'
  | 'locations'
  | 'location'
  | 'checkup'
  | 'results'
  | 'about'
  | 'contact'
  | 'privacy'
  | 'terms'
  | 'not-found';

export interface Crumb {
  name: string;
  path: string;
}

export interface RouteDef {
  path: string;
  kind: PageKind;
  slug?: string;
  /** Page title without the brand suffix. */
  title: string;
  description: string;
  breadcrumbs: Crumb[];
  changefreq: 'weekly' | 'monthly' | 'yearly';
  priority: number;
  noindex?: boolean;
  /** schema.org WebPage subtype */
  webPageType: 'WebPage' | 'CollectionPage' | 'AboutPage' | 'ContactPage' | 'ItemPage';
}

const home: Crumb = { name: 'Home', path: '/' };
const crumbs = (...c: Crumb[]): Crumb[] => [home, ...c];

const pkgCrumb = { name: 'Packages', path: '/packages' };
const svcCrumb = { name: 'Services', path: '/services' };
const indCrumb = { name: 'Industries', path: '/industries' };
const locCrumb = { name: 'Locations', path: '/locations' };
const melCrumb = { name: 'Melbourne', path: '/locations/melbourne' };

export const routes: RouteDef[] = [
  {
    path: '/',
    kind: 'home',
    title: 'Local Marketing for Melbourne Small Business',
    description:
      "Big Cat Marketing is Melbourne's local marketing team for small business. Show up on Google Maps, in local search and across your community.",
    breadcrumbs: [home],
    changefreq: 'weekly',
    priority: 1,
    webPageType: 'WebPage',
  },
  {
    path: '/packages',
    kind: 'packages',
    title: 'Local Marketing Packages & Pricing',
    description:
      'Bronze, Silver and Gold local marketing packages from $495/month + GST, plus custom Big Cat Growth plans. Clear inclusions, no ranking promises.',
    breadcrumbs: crumbs(pkgCrumb),
    changefreq: 'monthly',
    priority: 0.9,
    webPageType: 'CollectionPage',
  },
  ...packages.map<RouteDef>((p) => ({
    path: `/packages/${p.slug}`,
    kind: 'package',
    slug: p.slug,
    title: p.seoTitle,
    description: p.seoDescription,
    breadcrumbs: crumbs(pkgCrumb, { name: `${p.name} — ${p.theme}`, path: `/packages/${p.slug}` }),
    changefreq: 'monthly',
    priority: 0.8,
    webPageType: 'ItemPage',
  })),
  {
    path: '/services',
    kind: 'services',
    title: 'Local Marketing Services for Small Business',
    description:
      'Local SEO, Google Business Profile, reviews, websites, local ads, social, content, email & SMS, branding and campaigns — everything you need to win locally.',
    breadcrumbs: crumbs(svcCrumb),
    changefreq: 'monthly',
    priority: 0.8,
    webPageType: 'CollectionPage',
  },
  ...services.map<RouteDef>((s) => ({
    path: `/services/${s.slug}`,
    kind: 'service',
    slug: s.slug,
    title: s.seoTitle,
    description: s.seoDescription,
    breadcrumbs: crumbs(svcCrumb, { name: s.name, path: `/services/${s.slug}` }),
    changefreq: 'monthly',
    priority: 0.7,
    webPageType: 'WebPage',
  })),
  {
    path: '/industries',
    kind: 'industries',
    title: 'Local Marketing by Industry',
    description:
      'Local marketing built around your industry: trades, professional services, health and beauty, hospitality, retail and property.',
    breadcrumbs: crumbs(indCrumb),
    changefreq: 'monthly',
    priority: 0.7,
    webPageType: 'CollectionPage',
  },
  ...industries.map<RouteDef>((i) => ({
    path: `/industries/${i.slug}`,
    kind: 'industry',
    slug: i.slug,
    title: i.seoTitle,
    description: i.seoDescription,
    breadcrumbs: crumbs(indCrumb, { name: i.name, path: `/industries/${i.slug}` }),
    changefreq: 'monthly',
    priority: 0.6,
    webPageType: 'WebPage',
  })),
  {
    path: '/locations',
    kind: 'locations',
    title: 'Areas We Serve — Melbourne, Victoria & Australia',
    description:
      'Melbourne-based local marketing: in person or by video across Greater Melbourne, by video in Geelong and regional Victoria, and fully remote Australia-wide.',
    breadcrumbs: crumbs(locCrumb),
    changefreq: 'monthly',
    priority: 0.8,
    webPageType: 'CollectionPage',
  },
  ...locations.map<RouteDef>((l) => ({
    path: l.path,
    kind: 'location',
    slug: l.slug,
    title: l.seoTitle,
    description: l.seoDescription,
    breadcrumbs:
      l.parent === 'melbourne'
        ? crumbs(locCrumb, melCrumb, { name: l.shortName, path: l.path })
        : crumbs(locCrumb, { name: l.shortName, path: l.path }),
    changefreq: 'monthly',
    priority: l.slug === 'melbourne' ? 0.9 : 0.7,
    webPageType: l.slug === 'melbourne' ? 'CollectionPage' : 'WebPage',
  })),
  {
    path: '/local-visibility-checkup',
    kind: 'checkup',
    title: 'Free Local Visibility Check-up',
    description:
      'How visible is your business in your area? Get a free local visibility check-up covering your Google profile, reviews, website local signals and more.',
    breadcrumbs: crumbs({ name: 'Free Local Visibility Check-up', path: '/local-visibility-checkup' }),
    changefreq: 'monthly',
    priority: 0.9,
    webPageType: 'WebPage',
  },
  {
    path: '/results',
    kind: 'results',
    title: 'Results & Case Studies',
    description:
      'Approved case studies from Big Cat Marketing clients, tagged by region and industry. We only publish results our clients have approved.',
    breadcrumbs: crumbs({ name: 'Results', path: '/results' }),
    changefreq: 'monthly',
    priority: 0.6,
    webPageType: 'CollectionPage',
  },
  {
    path: '/about',
    kind: 'about',
    title: 'About Big Cat Marketing',
    description:
      "About Big Cat Marketing, Melbourne's local marketing team for small business. How we work, where we work and what we will — and won't — promise.",
    breadcrumbs: crumbs({ name: 'About', path: '/about' }),
    changefreq: 'yearly',
    priority: 0.6,
    webPageType: 'AboutPage',
  },
  {
    path: '/contact',
    kind: 'contact',
    title: 'Contact Big Cat Marketing',
    description:
      'Talk to Big Cat Marketing. Meet in person or by video in Greater Melbourne, or by video anywhere in Australia.',
    breadcrumbs: crumbs({ name: 'Contact', path: '/contact' }),
    changefreq: 'yearly',
    priority: 0.7,
    webPageType: 'ContactPage',
  },
  {
    path: '/privacy',
    kind: 'privacy',
    title: 'Privacy Policy',
    description: 'How Big Cat Marketing collects, uses, stores and protects your personal information.',
    breadcrumbs: crumbs({ name: 'Privacy Policy', path: '/privacy' }),
    changefreq: 'yearly',
    priority: 0.2,
    webPageType: 'WebPage',
  },
  {
    path: '/terms',
    kind: 'terms',
    title: 'Website Terms of Use',
    description: 'The terms that apply when you use the Big Cat Marketing website.',
    breadcrumbs: crumbs({ name: 'Terms of Use', path: '/terms' }),
    changefreq: 'yearly',
    priority: 0.2,
    webPageType: 'WebPage',
  },
];

export const notFoundRoute: RouteDef = {
  path: '/404',
  kind: 'not-found',
  title: 'Page Not Found',
  description: 'Sorry, we could not find that page.',
  breadcrumbs: [home],
  changefreq: 'yearly',
  priority: 0,
  noindex: true,
  webPageType: 'WebPage',
};

export function normalisePath(path: string): string {
  const p = (path.split(/[?#]/)[0] ?? '/').replace(/\/{2,}/g, '/');
  if (p.length > 1 && p.endsWith('/')) return p.slice(0, -1);
  return p || '/';
}

export function findRoute(path: string): RouteDef | undefined {
  const p = normalisePath(path);
  return routes.find((r) => r.path === p);
}

export const BRAND_SUFFIX = ' | Big Cat Marketing';

export function fullTitle(route: RouteDef): string {
  return route.kind === 'home' ? `Big Cat Marketing — ${route.title}` : `${route.title}${BRAND_SUFFIX}`;
}
