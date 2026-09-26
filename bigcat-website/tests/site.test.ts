import { describe, expect, it } from 'vitest';
import { routes, fullTitle } from '../src/routes';
import { renderPage } from '../src/entry-server';
import { business, outstandingFacts } from '../src/data/business';
import { locations } from '../src/data/locations';
import { industries } from '../src/data/industries';
import { services } from '../src/data/services';
import { packages } from '../src/data/packages';
import { caseStudies } from '../src/data/caseStudies';
import { buildGraph, faqsForRoute } from '../src/seo/schema';

const REQUIRED_ROUTES = `/ /packages /packages/bronze /packages/silver /packages/gold
/services /services/local-seo /services/google-business-profile /services/reviews
/services/websites /services/local-ads /services/social-media /services/content
/services/email-sms /services/branding /services/campaigns
/industries /industries/trades /industries/professional-services
/industries/health-beauty /industries/hospitality /industries/retail /industries/property
/locations /locations/melbourne
/locations/melbourne/inner-melbourne /locations/melbourne/northern-suburbs
/locations/melbourne/eastern-suburbs /locations/melbourne/south-east-bayside
/locations/melbourne/western-suburbs /locations/melbourne/outer-growth-corridors
/locations/regional-victoria /locations/australia
/local-visibility-checkup /results /about /contact /privacy /terms`.split(/\s+/);

const assets = { scripts: [], styles: [], preloads: [] };

describe('route registry', () => {
  it('contains exactly the required public routes', () => {
    expect(routes.map((r) => r.path).sort()).toEqual([...REQUIRED_ROUTES].sort());
  });
  it('has unique titles and descriptions', () => {
    expect(new Set(routes.map(fullTitle)).size).toBe(routes.length);
    expect(new Set(routes.map((r) => r.description)).size).toBe(routes.length);
  });
  it('only puts a location in the title where location is the page focus', () => {
    const places = /Melbourne|Geelong|Victoria|Coburg|Fitzroy|Bayside/;
    for (const r of routes) {
      if (['service', 'industry', 'package', 'services', 'industries', 'packages', 'about', 'privacy', 'terms', 'checkup', 'results'].includes(r.kind)) {
        expect(r.title, r.path).not.toMatch(places);
      }
    }
  });
});

describe('prerendered pages', () => {
  it.each(routes.map((r) => [r.path]))('%s renders full content with one h1', async (path) => {
    const page = await renderPage(path, assets);
    expect(page.status).toBe(200);
    expect(page.html.match(/<h1[\s>]/g)?.length).toBe(1);
    expect(page.html).toContain('<link rel="canonical"');
    expect(page.html).toContain('application/ld+json');
    expect(page.html).toContain(business.serviceAreaLine.replace('&', '&amp;'));
    expect(page.html).not.toMatch(/\bundefined\b|\[object Object\]/);
  });
  it('unknown URLs render the 404 page with noindex', async () => {
    const page = await renderPage('/no-such-page', assets);
    expect(page.status).toBe(404);
    expect(page.html).toContain('noindex');
  });
  it('homepage sections appear in the specified order', async () => {
    const { html } = await renderPage('/', assets);
    const order = [
      'Get found by the customers near you.',
      'Your customers are searching nearby.',
      'Found. Trusted. Chosen.',
      'Choose how much of your area you want to own.',
      'Everything your business needs to win locally.',
      'Local to Melbourne. Available Australia-wide.',
      'Local marketing built around your industry.',
      'How visible is your business in your area?',
      'Ready to be the business locals find first?',
    ].map((s) => html.indexOf(s));
    expect(order.every((i) => i > 0)).toBe(true);
    expect([...order].sort((a, b) => a - b)).toEqual(order);
  });
  it('hides the Proof section while there are no approved case studies', async () => {
    expect(caseStudies).toHaveLength(0);
    const { html } = await renderPage('/', assets);
    expect(html).not.toContain('id="proof-heading"');
  });
  it('shows all package prices + GST on the homepage', async () => {
    const { html } = await renderPage('/', assets);
    for (const p of ['$495', '$995', '$1,795']) expect(html).toContain(p);
    expect(html).toContain('/month + GST');
  });
});

describe('structured data', () => {
  it('never publishes an address while address.isPublic is false', () => {
    for (const r of routes) expect(JSON.stringify(buildGraph(r, 't'))).not.toContain('PostalAddress');
  });
  it('adds FAQPage only where FAQs exist', () => {
    for (const r of routes) {
      const has = JSON.stringify(buildGraph(r, 't')).includes('"FAQPage"');
      expect(has, r.path).toBe(faqsForRoute(r).length > 0);
    }
  });
  it('adds Service schema with areaServed to every service page', () => {
    for (const r of routes.filter((x) => x.kind === 'service')) {
      const g = JSON.stringify(buildGraph(r, 't'));
      expect(g).toContain('"@type":"Service"');
      expect(g).toContain('areaServed');
    }
  });
  it('prices packages ex GST in AUD', () => {
    const g = JSON.stringify(buildGraph(routes.find((r) => r.path === '/packages/gold')!, 't'));
    expect(g).toContain('"price":"1795.00"');
    expect(g).toContain('"valueAddedTaxIncluded":false');
  });
});

describe('content integrity', () => {
  const words = (s: string) => new Set(s.toLowerCase().match(/[a-z']+/g) ?? []);
  const jaccard = (a: Set<string>, b: Set<string>) => [...a].filter((x) => b.has(x)).length / new Set([...a, ...b]).size;

  it('location pages are not templated duplicates', () => {
    for (let i = 0; i < locations.length; i++) {
      for (let j = i + 1; j < locations.length; j++) {
        const a = locations[i]!;
        const b = locations[j]!;
        const sim = jaccard(words([...a.intro, ...a.landscape].join(' ')), words([...b.intro, ...b.landscape].join(' ')));
        expect(sim, `${a.slug} vs ${b.slug}`).toBeLessThan(0.45);
      }
    }
  });
  it('every location and industry is flagged for human review until approved', () => {
    for (const l of locations) if (l.reviewStatus !== 'approved') expect(l.needsReview.length, l.slug).toBeGreaterThan(0);
    for (const i of industries) if (i.reviewStatus !== 'approved') expect(i.needsReview.length, i.slug).toBeGreaterThan(0);
  });
  it('internal cross-references resolve', () => {
    const svc = new Set(services.map((s) => s.slug));
    const ind = new Set(industries.map((s) => s.slug));
    const loc = new Set(locations.map((s) => s.slug));
    for (const l of locations) {
      l.relevantServices.forEach((s) => expect(svc.has(s), s).toBe(true));
      l.commonIndustries.forEach((s) => expect(ind.has(s), s).toBe(true));
    }
    for (const i of industries) {
      i.relatedLocations.forEach((s) => expect(loc.has(s), s).toBe(true));
      i.serviceMapping.forEach((m) => expect(svc.has(m.service), m.service).toBe(true));
    }
    for (const p of packages) p.relatedServices.forEach((s) => expect(svc.has(s), s).toBe(true));
  });
  it('makes no ranking or lead-number guarantees', () => {
    const all = JSON.stringify({ services, industries, locations, packages });
    expect(all).not.toMatch(/\b(we|will|we'll) guarantee/i);
    expect(all).not.toMatch(/guaranteed (#1|number one|first page|top \d|rankings?|leads|results)/i);
    expect(all).not.toMatch(/\b\d+% (more|increase)/i);
  });
  it('reports outstanding business facts rather than inventing them', () => {
    const keys = outstandingFacts().map((f) => f.key);
    if (business.phone === null) expect(keys).toContain('phone');
    if (business.email === null) expect(keys).toContain('email');
  });
});
