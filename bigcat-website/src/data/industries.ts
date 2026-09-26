import type { PackageSlug } from './packages';
import type { Faq } from './services';

/**
 * Industry pages. Copy is general and must not claim clients, results or
 * partnerships. Fields marked in `needsReview` should be checked by someone
 * with real industry and local knowledge before production.
 */
export type ReviewStatus = 'draft-needs-review' | 'approved';

export interface Industry {
  slug: string;
  name: string;
  seoTitle: string;
  seoDescription: string;
  cardSummary: string;
  heroTitle: string;
  heroBody: string;
  intro: string[];
  examples: string[];
  /** Example local searches (illustrative, not measured search volumes). */
  searchExamples: string[];
  challenges: string[];
  serviceMapping: { service: string; why: string }[];
  faqs: Faq[];
  relatedLocations: string[];
  recommendedPackage: PackageSlug;
  reviewStatus: ReviewStatus;
  needsReview: string[];
}

export const industries: Industry[] = [
  {
    slug: 'trades',
    name: 'Trades & Home Services',
    seoTitle: 'Local Marketing for Tradies & Home Services',
    seoDescription:
      'Local marketing for plumbers, electricians, builders and home services: Google Business Profile, reviews, local SEO and ads for the suburbs you work in.',
    cardSummary: 'Plumbers, electricians, builders, landscapers and cleaners.',
    heroTitle: 'Win more jobs in the suburbs you actually want to work in.',
    heroBody:
      'When a hot water system fails or a fence comes down, people grab their phone and call one of the first few businesses they see. We help tradies be one of them — in the right areas.',
    intro: [
      'Most trade enquiries start with an urgent local search. Customers compare a few Maps listings, check the reviews and call.',
      'Trades are usually service-area businesses: you travel to the customer, and your address may not be public. That makes a correctly set-up Google Business Profile and clear service-area pages especially important.',
    ],
    examples: ['Plumbers', 'Electricians', 'Builders and renovators', 'Landscapers', 'Cleaners', 'Pest control', 'Locksmiths'],
    searchExamples: [
      'emergency plumber near me',
      'electrician [suburb]',
      'bathroom renovation [region]',
      'blocked drain same day',
      'licensed builder [suburb]',
    ],
    challenges: [
      'Being shown for jobs too far away to be profitable',
      'Competing with large franchises and lead-generation sites',
      'Getting busy customers to leave a review after the job',
      'Missing calls while on the tools',
    ],
    serviceMapping: [
      { service: 'google-business-profile', why: 'Set up as a service-area business with the right categories and services.' },
      { service: 'reviews', why: 'A simple way to ask for reviews straight after each job.' },
      { service: 'local-seo', why: 'Service-area pages for the regions you want more work in.' },
      { service: 'local-ads', why: 'Local Services Ads and Google Ads where eligible, targeted to your area.' },
    ],
    faqs: [
      {
        q: 'Can you stop me getting enquiries from too far away?',
        a: 'We can focus your profile, pages and ads on the areas you want. Google still decides who sees what, but tight targeting reduces wasted enquiries.',
      },
      {
        q: 'Do I need to show my home address on Google?',
        a: 'No. Service-area businesses can hide their address and show the areas they serve instead.',
      },
    ],
    relatedLocations: ['northern-suburbs', 'western-suburbs', 'outer-growth-corridors', 'regional-victoria'],
    recommendedPackage: 'silver',
    reviewStatus: 'draft-needs-review',
    needsReview: ['intro', 'examples', 'searchExamples', 'challenges', 'faqs', 'relatedLocations'],
  },
  {
    slug: 'professional-services',
    name: 'Professional Services',
    seoTitle: 'Local Marketing for Professional Services Firms',
    seoDescription:
      'Local marketing for accountants, lawyers, financial advisers and consultants: build trust, show expertise and get found by nearby clients.',
    cardSummary: 'Accountants, lawyers, advisers, consultants and agencies.',
    heroTitle: 'Clients want a trusted local expert. Make it easy to choose you.',
    heroBody:
      'Choosing an accountant, lawyer or adviser is a considered decision. Clients research, compare and ask around. Clear local content and strong reviews help them decide.',
    intro: [
      'Professional services clients often search for a specialist in their area, then read carefully before making contact.',
      'Clear service pages, genuine reviews, helpful articles and a consistent presence on LinkedIn build the trust that turns a search into a consultation.',
    ],
    examples: ['Accountants and bookkeepers', 'Lawyers and conveyancers', 'Financial advisers', 'Consultants', 'Architects', 'IT support'],
    searchExamples: [
      'accountant near me',
      'tax agent [suburb]',
      'family lawyer [region]',
      'conveyancer [suburb]',
      'small business accountant Melbourne',
    ],
    challenges: [
      'Explaining specialist services in plain language',
      'Standing out from larger firms in the same area',
      'Staying within professional advertising rules for your field',
      'Building trust before the first conversation',
    ],
    serviceMapping: [
      { service: 'content', why: 'Plain-English articles and FAQs that show expertise.' },
      { service: 'local-seo', why: 'Service pages that match how clients search.' },
      { service: 'reviews', why: 'Compliant ways to gather client feedback where permitted.' },
      { service: 'social-media', why: 'LinkedIn and Facebook posts that keep you front of mind.' },
    ],
    faqs: [
      {
        q: 'Our profession has advertising rules. Can you work within them?',
        a: 'Yes. We ask about your professional obligations up front and you approve all copy. You remain responsible for compliance with your professional body.',
      },
      {
        q: 'Is LinkedIn worth it for a local firm?',
        a: 'Often, yes — particularly for business-to-business services. Gold includes LinkedIn posting where appropriate.',
      },
    ],
    relatedLocations: ['inner-melbourne', 'eastern-suburbs', 'south-east-bayside', 'australia'],
    recommendedPackage: 'silver',
    reviewStatus: 'draft-needs-review',
    needsReview: ['intro', 'examples', 'searchExamples', 'challenges', 'faqs', 'relatedLocations'],
  },
  {
    slug: 'health-beauty',
    name: 'Health, Wellness & Beauty',
    seoTitle: 'Local Marketing for Clinics, Salons & Wellness',
    seoDescription:
      'Local marketing for clinics, physios, dentists, salons and wellness studios: more bookings from nearby clients, better reviews and a steady local presence.',
    cardSummary: 'Clinics, allied health, dentists, salons, gyms and studios.',
    heroTitle: 'Fill your appointment book with clients who live nearby.',
    heroBody:
      'Most clinic, salon and studio clients come from a few kilometres away. Being easy to find, easy to trust and easy to book makes the difference.',
    intro: [
      'Health and beauty clients choose on convenience and trust: how close you are, what others say and how easy it is to book.',
      'A complete profile, a steady flow of reviews, online booking and timely reminders help clients choose you and come back.',
    ],
    examples: ['Physiotherapists and allied health', 'Dentists', 'Hair and beauty salons', 'Massage and wellness', 'Gyms and studios', 'Vets'],
    searchExamples: [
      'physio near me',
      'dentist [suburb]',
      'hairdresser open Saturday [suburb]',
      'pilates studio [region]',
      'massage [suburb]',
    ],
    challenges: [
      'Health advertising rules (for example, AHPRA rules on testimonials for regulated health services)',
      'Filling quieter days and times',
      'Converting profile views into bookings',
      'Encouraging repeat visits',
    ],
    serviceMapping: [
      { service: 'google-business-profile', why: 'Booking links, services and photos front and centre.' },
      { service: 'reviews', why: 'Review programs that respect health advertising rules where they apply.' },
      { service: 'email-sms', why: 'Reminders and rebooking campaigns for existing clients.' },
      { service: 'social-media', why: 'Regular posts that show your space, team and expertise.' },
    ],
    faqs: [
      {
        q: 'Can regulated health services use reviews and testimonials?',
        a: 'Regulated health practitioners must follow AHPRA’s advertising guidelines, which restrict the use of testimonials in advertising. We work within those rules and you approve all content.',
      },
      {
        q: 'Can you link Google to our booking system?',
        a: 'Many booking systems can be linked from your Google Business Profile. We will check what your system supports.',
      },
    ],
    relatedLocations: ['eastern-suburbs', 'south-east-bayside', 'inner-melbourne', 'regional-victoria'],
    recommendedPackage: 'silver',
    reviewStatus: 'draft-needs-review',
    needsReview: ['intro', 'examples', 'searchExamples', 'challenges', 'faqs', 'relatedLocations'],
  },
  {
    slug: 'hospitality',
    name: 'Hospitality',
    seoTitle: 'Local Marketing for Cafés, Restaurants & Bars',
    seoDescription:
      'Local marketing for cafés, restaurants, bars and venues: accurate Maps listings, great photos, reviews and social that bring locals and visitors in.',
    cardSummary: 'Cafés, restaurants, bars, venues and caterers.',
    heroTitle: 'Be the place locals pick when they are deciding where to go.',
    heroBody:
      'Hungry people decide fast, usually from a map on their phone. Accurate hours, great photos, recent reviews and an easy-to-find menu win the visit.',
    intro: [
      'Hospitality decisions happen in minutes. People search nearby, glance at photos and reviews, check you are open and go.',
      'Keeping hours, menus and photos current and responding to reviews makes a visible difference to how your venue comes across.',
    ],
    examples: ['Cafés', 'Restaurants', 'Bars and pubs', 'Function venues', 'Caterers', 'Food trucks'],
    searchExamples: [
      'cafe near me',
      'breakfast [suburb]',
      'restaurants open now',
      'function room [region]',
      'best coffee [suburb]',
    ],
    challenges: [
      'Wrong hours on Google, especially on public holidays',
      'Out-of-date menus and photos',
      'Responding to reviews quickly and calmly',
      'Standing out on a busy strip',
    ],
    serviceMapping: [
      { service: 'google-business-profile', why: 'Accurate hours, menus, photos and attributes.' },
      { service: 'reviews', why: 'Thoughtful replies to every review.' },
      { service: 'social-media', why: 'Posts that show specials, events and atmosphere.' },
      { service: 'campaigns', why: 'Seasonal menus, events and openings promoted across channels.' },
    ],
    faqs: [
      {
        q: 'How do we keep public holiday hours right?',
        a: 'We update special hours in your Google Business Profile ahead of public holidays so customers do not turn up to a closed door.',
      },
      {
        q: 'Can you help with an opening?',
        a: 'Yes. Openings are a good fit for a local campaign across your profile, social, email and ads.',
      },
    ],
    relatedLocations: ['inner-melbourne', 'south-east-bayside', 'western-suburbs', 'regional-victoria'],
    recommendedPackage: 'bronze',
    reviewStatus: 'draft-needs-review',
    needsReview: ['intro', 'examples', 'searchExamples', 'challenges', 'faqs', 'relatedLocations'],
  },
  {
    slug: 'retail',
    name: 'Retail',
    seoTitle: 'Local Marketing for Independent Retailers',
    seoDescription:
      'Local marketing for independent shops and boutiques: get found by nearby shoppers, show what is in store and bring people through the door.',
    cardSummary: 'Independent shops, boutiques, garden centres and showrooms.',
    heroTitle: 'Give nearby shoppers a reason to walk through your door.',
    heroBody:
      'Shoppers often check online before they visit: is it open, do they stock it, is it worth the trip? We help independent retailers answer those questions clearly.',
    intro: [
      'Independent retailers compete with big chains and online stores. Local visibility, personality and service are where you win.',
      'Keeping your profile, products and social current — and giving locals reasons to return — turns browsers into regulars.',
    ],
    examples: ['Boutiques and fashion', 'Gift and homewares', 'Garden centres', 'Bike and outdoor stores', 'Showrooms', 'Specialty food'],
    searchExamples: [
      'gift shop near me',
      'homewares [suburb]',
      'bike shop [region]',
      'nursery open Sunday',
      'furniture showroom [suburb]',
    ],
    challenges: [
      'Competing with national chains and online marketplaces',
      'Showing what is in stock',
      'Driving visits on quieter days',
      'Turning one-off shoppers into regulars',
    ],
    serviceMapping: [
      { service: 'google-business-profile', why: 'Products, photos and hours kept current.' },
      { service: 'social-media', why: 'New stock, events and behind-the-scenes posts.' },
      { service: 'email-sms', why: 'Offers and news for your regular customers.' },
      { service: 'branding', why: 'A consistent look across shopfront, bags, site and social.' },
    ],
    faqs: [
      {
        q: 'Do you build online stores?',
        a: 'eCommerce builds are scoped under Big Cat Growth. Our packages focus on local visibility and bringing people in store.',
      },
      {
        q: 'Can you promote a sale or event?',
        a: 'Yes. Sales, launches and events suit a coordinated local campaign.',
      },
    ],
    relatedLocations: ['inner-melbourne', 'eastern-suburbs', 'northern-suburbs', 'regional-victoria'],
    recommendedPackage: 'bronze',
    reviewStatus: 'draft-needs-review',
    needsReview: ['intro', 'examples', 'searchExamples', 'challenges', 'faqs', 'relatedLocations'],
  },
  {
    slug: 'property',
    name: 'Property & Real Estate',
    seoTitle: 'Local Marketing for Real Estate & Property Businesses',
    seoDescription:
      'Local marketing for real estate agents, property managers, mortgage brokers and property services: suburb expertise, reviews and local content.',
    cardSummary: 'Agents, property managers, brokers and property services.',
    heroTitle: 'Show vendors and landlords you know their area.',
    heroBody:
      'Property decisions are local and high value. Vendors, buyers and landlords look for someone who clearly knows the area and has a strong reputation.',
    intro: [
      'Property businesses depend on local reputation. Clients want proof that you know the streets, the market and the community.',
      'Useful local content, strong reviews and a consistent presence build that reputation over time.',
    ],
    examples: ['Real estate agents', 'Property managers', 'Mortgage brokers', 'Building inspectors', 'Removalists', 'Stylists'],
    searchExamples: [
      'real estate agent [suburb]',
      'property management [region]',
      'mortgage broker near me',
      'building inspection [suburb]',
      'removalist [region]',
    ],
    challenges: [
      'Competing with large portals for attention',
      'Showing genuine local knowledge without making claims you cannot back up',
      'Gathering reviews from vendors and landlords',
      'Consistent branding across agents and offices',
    ],
    serviceMapping: [
      { service: 'content', why: 'Genuinely useful area guides written with your local knowledge.' },
      { service: 'reviews', why: 'A process for asking every happy vendor, buyer or landlord.' },
      { service: 'local-ads', why: 'Appraisal and property management campaigns in target areas.' },
      { service: 'campaigns', why: 'Seasonal listing and appraisal campaigns.' },
    ],
    faqs: [
      {
        q: 'Can you write suburb guides for us?',
        a: 'Yes, with your input. Suburb guides need real local knowledge, so we interview you and never publish claims we cannot verify.',
      },
      {
        q: 'Do you publish market statistics?',
        a: 'Only from sources you are licensed to use and that we can cite. We do not invent figures.',
      },
    ],
    relatedLocations: ['eastern-suburbs', 'south-east-bayside', 'outer-growth-corridors', 'regional-victoria'],
    recommendedPackage: 'gold',
    reviewStatus: 'draft-needs-review',
    needsReview: ['intro', 'examples', 'searchExamples', 'challenges', 'faqs', 'relatedLocations'],
  },
];

export function getIndustry(slug: string): Industry | undefined {
  return industries.find((i) => i.slug === slug);
}
