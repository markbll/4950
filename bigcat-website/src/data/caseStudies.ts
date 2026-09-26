/**
 * APPROVED case studies only.
 *
 * Add an entry only when:
 *  1. the client has given written approval to be named (store it outside this repo), and
 *  2. every figure can be backed by data you can show the client.
 *
 * The homepage Proof section and case-study lists hide automatically while
 * this array is empty. Never add placeholder, sample or invented results.
 */
export interface CaseStudy {
  slug: string;
  client: string;
  /** Location slug from locations.ts, e.g. 'northern-suburbs'. */
  region: string;
  /** Industry slug from industries.ts, e.g. 'trades'. */
  industry: string;
  package: 'bronze' | 'silver' | 'gold' | 'custom';
  summary: string;
  whatWeDid: string[];
  /** Verifiable outcomes, each with its measurement source and period. */
  outcomes: { text: string; source: string; period: string }[];
  approvedBy: string;
  approvedOn: string; // ISO date
}

export const caseStudies: CaseStudy[] = [];

export const caseStudiesFor = (filter: { region?: string; industry?: string }): CaseStudy[] =>
  caseStudies.filter(
    (c) => (!filter.region || c.region === filter.region) && (!filter.industry || c.industry === filter.industry),
  );
