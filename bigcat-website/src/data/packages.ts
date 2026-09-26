/**
 * Package definitions. All prices are ex GST; advertising spend is always
 * separate and paid by the client. Never promise rankings, Map Pack
 * positions or lead numbers in any package copy.
 */
export type PackageSlug = 'bronze' | 'silver' | 'gold';

export interface Package {
  slug: PackageSlug;
  name: string;
  theme: string;
  priceMonthly: number;
  summary: string;
  bestFor: string;
  includesPrevious: PackageSlug | null;
  inclusions: string[];
  /** Service slugs this package is closely associated with (internal linking). */
  relatedServices: string[];
  seoTitle: string;
  seoDescription: string;
  faqs: { q: string; a: string }[];
}

export const GST_NOTE = 'All prices are in Australian dollars, exclude GST, and exclude advertising spend.';

export const packages: Package[] = [
  {
    slug: 'bronze',
    name: 'Bronze',
    theme: 'Get Found Locally',
    priceMonthly: 495,
    summary:
      'The essentials for being found nearby: a properly set-up Google Business Profile, consistent business details, a steady stream of reviews and monthly local content.',
    bestFor:
      'Sole traders and small teams serving one main area who want the local basics done properly, every month.',
    includesPrevious: null,
    inclusions: [
      'Google Business Profile optimisation (categories, services, service areas, hours, photos, Q&A)',
      '4 Google Business Profile posts per month',
      'Local keyword map for 1 service area',
      'NAP audit and core citation fixes',
      'Website local SEO check',
      'Review-generation setup and review response drafting',
      '1 local SEO article or service-area page update per month',
      '2 social posts per month',
      'Search Console, Analytics and Google Business Profile insights monitoring',
      'Monthly local visibility summary',
      'Quarterly review',
    ],
    relatedServices: ['google-business-profile', 'local-seo', 'reviews'],
    seoTitle: 'Bronze Local Marketing Package — $495/month + GST',
    seoDescription:
      'Bronze: Google Business Profile optimisation, citations, reviews and monthly local content for small businesses. $495/month + GST. Ad spend separate.',
    faqs: [
      {
        q: 'Is there a lock-in contract?',
        a: 'Minimum terms are confirmed in your proposal before you sign anything. Local SEO takes time to build, so we will talk you through what is realistic before you commit.', // TODO(review): confirm minimum term policy
      },
      {
        q: 'Do you guarantee a spot in the Google Map Pack?',
        a: 'No. Nobody can honestly guarantee rankings or Map Pack positions — Google decides those. We do the work that gives you the best chance and report on what changes.',
      },
      {
        q: 'Can I upgrade later?',
        a: 'Yes. Many businesses start on Bronze and move to Silver when they are ready to target more areas or add email and ads.',
      },
    ],
  },
  {
    slug: 'silver',
    name: 'Silver',
    theme: 'Own Your Area',
    priceMonthly: 995,
    summary:
      'For businesses ready to compete across several suburbs: competitor research, rank tracking, more content, regular social, email or SMS, and conversion tracking so you can see what is working.',
    bestFor: 'Established local businesses serving up to three service areas who want to measure calls, forms and bookings.',
    includesPrevious: 'bronze',
    inclusions: [
      'Local keyword map for up to 3 service areas',
      'Local competitor research and local rank tracking',
      'Expanded citation building',
      '2 local content pieces per month',
      '8 social posts per month on Facebook and Instagram',
      '1 email or SMS campaign per month',
      'Local Google Ads setup (ongoing management optional)',
      'Conversion tracking for calls, forms, bookings and directions',
      'Monthly strategy meeting and report',
      'Quarterly local campaign planning',
    ],
    relatedServices: ['local-seo', 'social-media', 'email-sms', 'local-ads', 'content'],
    seoTitle: 'Silver Local Marketing Package — $995/month + GST',
    seoDescription:
      'Silver: local SEO for up to 3 service areas, competitor research, rank tracking, social, email/SMS and conversion tracking. $995/month + GST.',
    faqs: [
      {
        q: 'Is Google Ads management included?',
        a: 'Silver includes setting up a local Google Ads campaign. Ongoing management is optional and quoted separately. Your ad spend is always paid directly by you.',
      },
      {
        q: 'What counts as a service area?',
        a: 'A service area is a group of nearby suburbs or a town you want to be found in — for example, a cluster of bayside suburbs. We agree the three areas with you at the start.',
      },
      {
        q: 'Do you meet in person?',
        a: 'Yes, for businesses in Greater Melbourne we can meet in person or by video. Elsewhere, meetings are by video.',
      },
    ],
  },
  {
    slug: 'gold',
    name: 'Gold',
    theme: 'Lead Your Region',
    priceMonthly: 1795,
    summary:
      'A full local marketing team for multi-area or multi-location businesses: managed Google and Meta ads, a review program, local partnerships, monthly campaigns and a full local dashboard.',
    bestFor: 'Businesses with up to three locations, or a wide service area, who want local search, ads and reputation handled together.',
    includesPrevious: 'silver',
    inclusions: [
      'Up to 3 Google Business Profile locations or expanded service areas',
      '4 local content or SEO assets per month',
      '12 social posts per month, including LinkedIn where appropriate',
      'Local Google Ads management (including Local Services Ads where eligible)',
      'Local Meta Ads management',
      'Review program and reputation monitoring',
      'Local link and partnership building',
      'Up to 2 hours per month of minor website updates',
      '2 email or SMS campaigns per month',
      '1 local campaign per month',
      'Full monthly local dashboard',
      'Priority support',
    ],
    relatedServices: ['local-ads', 'reviews', 'campaigns', 'content', 'websites'],
    seoTitle: 'Gold Local Marketing Package — $1,795/month + GST',
    seoDescription:
      'Gold: multi-location local SEO, managed Google and Meta ads, review program, local partnerships and monthly campaigns. $1,795/month + GST.',
    faqs: [
      {
        q: 'Is ad spend included in the monthly fee?',
        a: 'No. The fee covers our management. Ad spend is separate, paid directly to Google or Meta, and agreed with you before any campaign goes live.',
      },
      {
        q: 'What are Local Services Ads?',
        a: 'Local Services Ads are a Google ad format for some service categories. Eligibility depends on your industry and Google’s verification requirements, so we check before recommending them.',
      },
      {
        q: 'We have more than three locations. Is Gold right for us?',
        a: 'For four or more locations, franchises or larger budgets, Big Cat Growth is usually a better fit. We scope it around your business.',
      },
    ],
  },
];

export const customPackage = {
  name: 'Big Cat Growth',
  theme: 'Custom',
  summary:
    'For 4+ locations, franchises, website rebuilds, eCommerce and larger advertising budgets. Scoped and quoted around your business.',
  examples: ['4 or more locations', 'Franchise networks', 'Website rebuilds', 'eCommerce', 'Larger ad budgets'],
};

export function getPackage(slug: string): Package | undefined {
  return packages.find((p) => p.slug === slug);
}

export function formatPrice(amount: number): string {
  return `$${amount.toLocaleString('en-AU')}`;
}
