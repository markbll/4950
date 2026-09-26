/**
 * JSON-LD generated from business.ts and the route registry.
 * One @graph per page: business entity, WebSite, WebPage, BreadcrumbList,
 * plus Service / Offer / FAQPage where relevant.
 */
import { absoluteUrl, business, sameAsLinks, type Business } from '../data/business';
import { getPackage, GST_NOTE } from '../data/packages';
import { getService, type Faq } from '../data/services';
import { getIndustry } from '../data/industries';
import { getLocation, melbourneRegions } from '../data/locations';
import type { RouteDef } from '../routes';

type Node = Record<string, unknown>;

const id = (frag: string) => `${absoluteUrl('/')}#${frag}`;
export const BUSINESS_ID = id('business');
export const WEBSITE_ID = id('website');

export function areaServed(): Node[] {
  const victoria = { '@type': 'AdministrativeArea', name: 'Victoria', containedInPlace: { '@type': 'Country', name: 'Australia' } };
  return [
    { '@type': 'City', name: 'Melbourne', containedInPlace: victoria },
    ...melbourneRegions().map((r) => ({ '@type': 'Place', name: `${r.name}, Melbourne`, containedInPlace: victoria })),
    { '@type': 'City', name: 'Geelong', containedInPlace: victoria },
    victoria,
    { '@type': 'Country', name: 'Australia' },
  ];
}

export function businessNode(b: Business = business): Node {
  const node: Node = {
    // Organization + the most specific accurate LocalBusiness subtype.
    '@type': ['Organization', 'ProfessionalService'],
    '@id': BUSINESS_ID,
    name: b.name,
    url: absoluteUrl('/'),
    description: b.description,
    slogan: b.tagline,
    logo: { '@type': 'ImageObject', url: absoluteUrl(b.logoPath) },
    image: absoluteUrl(b.logoPath),
    areaServed: areaServed(),
    knowsLanguage: 'en-AU',
  };
  if (b.legalName) node.legalName = b.legalName;
  if (b.phone) node.telephone = b.phone.e164;
  if (b.email) node.email = b.email;
  const sameAs = sameAsLinks(b);
  if (sameAs.length) node.sameAs = sameAs;
  if (b.abn) node.taxID = `ABN ${b.abn}`;
  if (b.address.isPublic && b.address.streetAddress) {
    node.address = {
      '@type': 'PostalAddress',
      streetAddress: b.address.streetAddress,
      addressLocality: b.address.locality,
      addressRegion: b.address.region,
      postalCode: b.address.postcode ?? undefined,
      addressCountry: b.address.country,
    };
  }
  if (b.hours?.length) {
    node.openingHoursSpecification = b.hours.map((h) => ({
      '@type': 'OpeningHoursSpecification',
      dayOfWeek: h.days,
      opens: h.opens,
      closes: h.closes,
    }));
  }
  if (b.phone || b.email) {
    node.contactPoint = {
      '@type': 'ContactPoint',
      contactType: 'sales',
      areaServed: 'AU',
      availableLanguage: 'en',
      ...(b.phone ? { telephone: b.phone.e164 } : {}),
      ...(b.email ? { email: b.email } : {}),
    };
  }
  return node;
}

function websiteNode(): Node {
  return {
    '@type': 'WebSite',
    '@id': WEBSITE_ID,
    url: absoluteUrl('/'),
    name: business.name,
    inLanguage: 'en-AU',
    publisher: { '@id': BUSINESS_ID },
  };
}

function breadcrumbNode(route: RouteDef): Node {
  return {
    '@type': 'BreadcrumbList',
    '@id': `${absoluteUrl(route.path)}#breadcrumb`,
    itemListElement: route.breadcrumbs.map((c, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: c.name,
      item: absoluteUrl(c.path),
    })),
  };
}

function webPageNode(route: RouteDef, title: string): Node {
  return {
    '@type': route.webPageType,
    '@id': `${absoluteUrl(route.path)}#webpage`,
    url: absoluteUrl(route.path),
    name: title,
    description: route.description,
    inLanguage: 'en-AU',
    isPartOf: { '@id': WEBSITE_ID },
    about: { '@id': BUSINESS_ID },
    breadcrumb: { '@id': `${absoluteUrl(route.path)}#breadcrumb` },
  };
}

export function faqNode(route: RouteDef, faqs: Faq[]): Node {
  return {
    '@type': 'FAQPage',
    '@id': `${absoluteUrl(route.path)}#faq`,
    mainEntity: faqs.map((f) => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a },
    })),
  };
}

/** FAQs shown on a route — also used by the page components so schema and page never drift. */
export function faqsForRoute(route: RouteDef): Faq[] {
  switch (route.kind) {
    case 'service':
      return getService(route.slug!)?.faqs ?? [];
    case 'industry':
      return getIndustry(route.slug!)?.faqs ?? [];
    case 'location':
      return getLocation(route.slug!)?.faqs ?? [];
    case 'package':
      return getPackage(route.slug!)?.faqs ?? [];
    default:
      return [];
  }
}

export function buildGraph(route: RouteDef, title: string): Node {
  const graph: Node[] = [businessNode(), websiteNode(), webPageNode(route, title), breadcrumbNode(route)];

  if (route.kind === 'service') {
    const s = getService(route.slug!);
    if (s) {
      graph.push({
        '@type': 'Service',
        '@id': `${absoluteUrl(route.path)}#service`,
        name: s.name,
        serviceType: s.serviceType,
        description: s.seoDescription,
        url: absoluteUrl(route.path),
        provider: { '@id': BUSINESS_ID },
        areaServed: areaServed(),
      });
    }
  }

  if (route.kind === 'package') {
    const p = getPackage(route.slug!);
    if (p) {
      graph.push({
        '@type': 'Service',
        '@id': `${absoluteUrl(route.path)}#service`,
        name: `${p.name} — ${p.theme}`,
        serviceType: 'Local marketing package',
        description: p.summary,
        url: absoluteUrl(route.path),
        provider: { '@id': BUSINESS_ID },
        areaServed: areaServed(),
        offers: {
          '@type': 'Offer',
          url: absoluteUrl(route.path),
          priceCurrency: 'AUD',
          price: p.priceMonthly.toFixed(2),
          availability: 'https://schema.org/InStock',
          priceSpecification: {
            '@type': 'UnitPriceSpecification',
            price: p.priceMonthly.toFixed(2),
            priceCurrency: 'AUD',
            unitText: 'MONTH',
            referenceQuantity: { '@type': 'QuantitativeValue', value: 1, unitCode: 'MON' },
            valueAddedTaxIncluded: false,
            description: GST_NOTE,
          },
        },
      });
    }
  }

  if (route.kind === 'location') {
    const l = getLocation(route.slug!);
    if (l) {
      (graph[2] as Node).about = [{ '@id': BUSINESS_ID }, { '@type': 'Place', name: l.name }];
    }
  }

  const faqs = faqsForRoute(route);
  if (faqs.length) graph.push(faqNode(route, faqs));

  return { '@context': 'https://schema.org', '@graph': graph };
}

/** Serialise JSON for a <script type="application/ld+json"> without allowing tag break-out. */
export function jsonLdScript(data: unknown): string {
  return JSON.stringify(data).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
}
