/**
 * SINGLE SOURCE OF TRUTH for Big Cat Marketing's business facts (NAP etc.).
 *
 * The footer NAP block, contact page, meta tags and JSON-LD all read from
 * this file. Do not hard-code any of these values anywhere else.
 *
 * RULES
 * - Never invent a fact. Anything not supplied by the business is `null`
 *   and tagged with a `TODO(fact)` comment.
 * - `npm run check:facts` lists outstanding TODOs. A production build
 *   (VITE_SITE_ENV=production) fails while any REQUIRED fact is still null.
 * - When a fact changes here, update Google Business Profile and every
 *   citation in docs/citation-register.csv to match exactly.
 */
import { siteConfig } from '../config';

export type ServiceTier = 'melbourne' | 'regional_vic' | 'remote';

export interface ServiceAreaTier {
  tier: ServiceTier;
  label: string;
  /** How we deliver work in this tier. Must stay accurate — no invented offices. */
  delivery: string;
  locationSlug: string;
}

export interface OpeningHours {
  /** schema.org day names, e.g. ['Monday', 'Tuesday'] */
  days: string[];
  opens: string; // 'HH:MM'
  closes: string; // 'HH:MM'
}

export interface Business {
  name: string;
  legalName: string | null;
  abn: string | null;
  tagline: string;
  description: string;
  url: string;
  logoPath: string;
  phone: { display: string; e164: string } | null;
  email: string | null;
  address: {
    /** Only publish the street address if the business explicitly approves it. */
    isPublic: boolean;
    streetAddress: string | null;
    locality: string;
    region: string;
    postcode: string | null;
    country: string;
  };
  /** Text used for the lazy Google Map embed. Service-area based, not a street address. */
  mapQuery: string;
  serviceAreaLine: string;
  serviceAreas: ServiceAreaTier[];
  hours: OpeningHours[] | null;
  hoursNote: string;
  googleBusinessProfileUrl: string | null;
  social: {
    facebook: string | null;
    instagram: string | null;
    linkedin: string | null;
  };
  /** Response-time promise used in forms and the check-up. Confirm with the team. */
  responseTime: string;
}

export const business: Business = {
  name: 'Big Cat Marketing',
  legalName: null, // TODO(fact): registered entity name, if different from trading name
  abn: '49 514 253 509',
  tagline: "Melbourne's local marketing team for small business.",
  description:
    'Big Cat Marketing is a Melbourne-based local marketing team for small and medium-sized businesses. We help businesses show up on Google Maps, in local search and across their community, working in person or by video across Greater Melbourne and remotely Australia-wide.',
  url: siteConfig.siteUrl,
  logoPath: '/logo.png', // TODO(fact): replace public/logo.png with the approved brand logo
  phone: { display: '0418 58 32 38', e164: '+61418583238' }, // must match Google Business Profile exactly
  email: 'info@bigcatmarketing.com.au',
  address: {
    isPublic: false, // TODO(fact): confirm whether a street address may be published
    streetAddress: null, // TODO(fact): only if isPublic is true
    locality: 'Melbourne',
    region: 'VIC',
    postcode: null, // TODO(fact): only if isPublic is true
    country: 'AU',
  },
  mapQuery: 'Melbourne VIC, Australia',
  serviceAreaLine: 'Melbourne-based · Working with small businesses across Australia',
  serviceAreas: [
    {
      tier: 'melbourne',
      label: 'Greater Melbourne',
      delivery: 'In person or by video',
      locationSlug: 'melbourne',
    },
    {
      tier: 'regional_vic',
      label: 'Geelong & regional Victoria',
      delivery: 'By video, in person by arrangement',
      locationSlug: 'regional-victoria',
    },
    {
      tier: 'remote',
      label: 'Rest of Australia',
      delivery: 'Fully remote',
      locationSlug: 'australia',
    },
  ],
  hours: null, // TODO(fact): e.g. [{ days: ['Monday','Tuesday','Wednesday','Thursday','Friday'], opens: '09:00', closes: '17:00' }]
  hoursNote: 'By appointment', // TODO(fact): confirm public hours wording
  googleBusinessProfileUrl: 'https://share.google/nSVP2PFLOOciJUyDQ',
  social: {
    facebook: 'https://facebook.com/bigcatmarketing',
    instagram: 'https://www.instagram.com/bigcatmarketing',
    linkedin: 'https://www.linkedin.com/company/bigcatmarketing',
  },
  responseTime: 'within 1 business day', // TODO(fact): confirm the team can meet this
};

export interface TodoFact {
  key: string;
  required: boolean;
  note: string;
}

/**
 * Outstanding business facts. `required` facts block a production build.
 */
export function outstandingFacts(b: Business = business): TodoFact[] {
  const list: TodoFact[] = [];
  const add = (cond: boolean, key: string, required: boolean, note: string) => {
    if (cond) list.push({ key, required, note });
  };
  add(b.phone === null, 'phone', true, 'Public phone number (display + E.164)');
  add(b.email === null, 'email', true, 'Public enquiries email');
  add(b.abn === null, 'abn', false, 'ABN for footer and terms');
  add(b.legalName === null, 'legalName', false, 'Registered entity name if different');
  add(b.hours === null, 'hours', false, 'Opening hours (optional for a service-area business)');
  add(b.googleBusinessProfileUrl === null, 'googleBusinessProfileUrl', false, 'GBP share URL (used in sameAs)');
  add(b.social.facebook === null, 'social.facebook', false, 'Facebook page URL');
  add(b.social.instagram === null, 'social.instagram', false, 'Instagram profile URL');
  add(b.social.linkedin === null, 'social.linkedin', false, 'LinkedIn page URL');
  add(b.address.isPublic && b.address.streetAddress === null, 'address.streetAddress', true, 'Street address (marked public)');
  return list;
}

export function sameAsLinks(b: Business = business): string[] {
  return [b.googleBusinessProfileUrl, b.social.facebook, b.social.instagram, b.social.linkedin].filter(
    (v): v is string => typeof v === 'string' && v.length > 0,
  );
}

export function absoluteUrl(path: string): string {
  if (/^https?:\/\//.test(path)) return path;
  return `${siteConfig.siteUrl}${path.startsWith('/') ? path : `/${path}`}`;
}
