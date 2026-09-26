import type { ServiceTier } from './business';
import type { Faq } from './services';
import type { ReviewStatus } from './industries';

/**
 * Location pages.
 *
 * - Every entry has UNIQUE copy. Do not clone an entry and swap place names.
 * - No individual suburb pages. Suburbs are referenced inside regions only.
 * - All copy is DRAFT until someone with genuine local knowledge has
 *   reviewed it. Fields listed in `needsReview` must be checked before
 *   production. Never add offices, partnerships, clients or statistics
 *   that cannot be verified.
 */
export interface Location {
  slug: string;
  path: string;
  name: string;
  /** Short label used in cards and breadcrumbs. */
  shortName: string;
  tier: ServiceTier;
  parent: string | null;
  seoTitle: string;
  seoDescription: string;
  h1: string;
  cardSummary: string;
  suburbs: string[];
  intro: string[];
  landscape: string[];
  searchChallenges: string[];
  relevantServices: string[];
  commonIndustries: string[];
  faqs: Faq[];
  /** Slugs of approved case studies only. */
  caseStudies: string[];
  meeting: 'in_person_or_video' | 'video_in_person_by_arrangement' | 'remote';
  reviewStatus: ReviewStatus;
  needsReview: string[];
}

export const melbourneRegionSlugs = [
  'inner-melbourne',
  'northern-suburbs',
  'eastern-suburbs',
  'south-east-bayside',
  'western-suburbs',
  'outer-growth-corridors',
] as const;

export const locations: Location[] = [
  {
    slug: 'melbourne',
    path: '/locations/melbourne',
    name: 'Greater Melbourne',
    shortName: 'Melbourne',
    tier: 'melbourne',
    parent: null,
    seoTitle: 'Local Marketing Melbourne — Small Business Local SEO',
    seoDescription:
      'Melbourne-based local marketing for small business across Greater Melbourne. Google Business Profile, local SEO, reviews and ads. Meet in person or by video.',
    h1: 'Local marketing for Melbourne small businesses',
    cardSummary: 'Our home base. Meet in person or by video anywhere in Greater Melbourne.',
    suburbs: [],
    intro: [
      'Melbourne is where we are based, and where we can meet you in person. Greater Melbourne is not one market, though — a café in Fitzroy and a builder in Tarneit are competing for very different customers, in very different searches.',
      'We plan your local marketing around the part of Melbourne you actually serve, from the inner city to the growth corridors.',
    ],
    landscape: [
      'Greater Melbourne covers inner-city strips, established middle-ring suburbs, industrial and logistics precincts, bayside villages and fast-growing new estates on the fringe.',
      'Customers in each area search differently and travel different distances, so a single “Melbourne” strategy rarely fits a local business.',
    ],
    searchChallenges: [
      'Map Pack results change street by street, so a business can be visible in one suburb and invisible in the next.',
      'Many industries have dozens of competitors within a few kilometres.',
      'Service-area businesses need to show clearly which parts of Melbourne they cover.',
    ],
    relevantServices: ['google-business-profile', 'local-seo', 'reviews', 'local-ads'],
    commonIndustries: ['trades', 'hospitality', 'health-beauty', 'professional-services', 'retail', 'property'],
    faqs: [
      {
        q: 'Can we meet in person?',
        a: 'Yes. Anywhere in Greater Melbourne we can meet in person or by video — whichever suits you.',
      },
      {
        q: 'Do you have an office I can visit?',
        a: 'We are Melbourne-based and meet clients at their business or by video. Please get in touch to arrange a time.', // TODO(fact): update if a public office address is approved
      },
      {
        q: 'Which parts of Melbourne do you cover?',
        a: 'All of Greater Melbourne: the inner city, northern, eastern, south-east and bayside, western suburbs and the outer growth corridors.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'inner-melbourne',
    path: '/locations/melbourne/inner-melbourne',
    name: 'Inner Melbourne',
    shortName: 'Inner Melbourne',
    tier: 'melbourne',
    parent: 'melbourne',
    seoTitle: 'Inner Melbourne Local Marketing & SEO',
    seoDescription:
      'Local marketing for small businesses in the CBD and inner suburbs: stand out in dense Map Pack results where competitors are a few doors away.',
    h1: 'Local marketing for Inner Melbourne businesses',
    cardSummary: 'CBD, Southbank, Carlton, Fitzroy, Collingwood, Richmond, South Yarra.',
    suburbs: ['Melbourne CBD', 'Southbank', 'Docklands', 'Carlton', 'Fitzroy', 'Collingwood', 'Richmond', 'South Yarra', 'Prahran', 'North Melbourne', 'East Melbourne', 'Abbotsford'],
    intro: [
      'In inner Melbourne your nearest competitor might be across the lane. When a customer searches from their phone, Google has a lot of businesses to choose from within a very small radius.',
      'Standing out here is about precision: the right categories, a profile that looks cared for, a stream of recent reviews and content that reflects your exact neighbourhood.',
    ],
    landscape: [
      'The inner city mixes office workers, residents, students and visitors. Well-known shopping and dining strips sit side by side with offices and apartments, and each strip has its own character.',
      'Many inner-city customers walk or take public transport, so being the closest good option at the moment they search matters.',
    ],
    searchChallenges: [
      'Very dense Map Pack competition in a small area',
      'Customers searching from a different suburb than where they live (for example, near work)',
      'Short decision windows — “open now” and “near me” searches',
      'Apartment and laneway addresses that are hard to find without clear directions',
    ],
    relevantServices: ['google-business-profile', 'reviews', 'social-media', 'content'],
    commonIndustries: ['hospitality', 'retail', 'professional-services', 'health-beauty'],
    faqs: [
      {
        q: 'Is it worth doing local SEO in the CBD when there is so much competition?',
        a: 'Yes, but it needs to be precise. Competition is high, so profile quality, reviews and relevance to your exact location matter even more.',
      },
      {
        q: 'Our customers work nearby but live elsewhere. Does that matter?',
        a: 'It does. Google often uses the searcher’s current location, so being visible around your street during working hours is valuable. We plan content and ads with that in mind.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'northern-suburbs',
    path: '/locations/melbourne/northern-suburbs',
    name: 'Northern Suburbs',
    shortName: 'Northern suburbs',
    tier: 'melbourne',
    parent: 'melbourne',
    seoTitle: 'Northern Suburbs Melbourne Local Marketing',
    seoDescription:
      'Local marketing for businesses in Melbourne’s north, from Brunswick and Coburg to Preston, Reservoir and Epping. Profiles, reviews and local SEO.',
    h1: 'Local marketing for Melbourne’s northern suburbs',
    cardSummary: 'Brunswick, Coburg, Northcote, Preston, Reservoir, Bundoora, Epping.',
    suburbs: ['Brunswick', 'Coburg', 'Pascoe Vale', 'Northcote', 'Thornbury', 'Preston', 'Reservoir', 'Bundoora', 'Thomastown', 'Epping', 'Glenroy', 'Broadmeadows'],
    intro: [
      'The north stretches from busy inner-north shopping strips to large residential and industrial areas further out. A business in Brunswick and a business in Epping can have very different customers.',
      'We help northern suburbs businesses be specific about the areas they serve, so they show up for the customers they actually want.',
    ],
    landscape: [
      'Inner-north suburbs have strong local identities and independent retail and hospitality. Further north, larger residential areas and industrial precincts support many trades and service businesses.',
      'Customers here often value independent, local businesses and will read reviews closely before choosing.',
    ],
    searchChallenges: [
      'Service areas that span both inner and outer north',
      'Competition from inner-city businesses for inner-north searches',
      'Trades competing with lead-generation sites',
      'Suburbs with similar names or overlapping boundaries',
    ],
    relevantServices: ['local-seo', 'google-business-profile', 'reviews', 'local-ads'],
    commonIndustries: ['trades', 'hospitality', 'retail', 'health-beauty'],
    faqs: [
      {
        q: 'We serve the whole north. Should we target every suburb?',
        a: 'Usually it is better to prioritise a few service areas that are closest or most profitable, then expand. We map that out in your keyword plan.',
      },
      {
        q: 'Can you meet us at our workshop or shop?',
        a: 'Yes. We can meet in person anywhere in Greater Melbourne, including the northern suburbs.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'eastern-suburbs',
    path: '/locations/melbourne/eastern-suburbs',
    name: 'Eastern Suburbs',
    shortName: 'Eastern suburbs',
    tier: 'melbourne',
    parent: 'melbourne',
    seoTitle: 'Eastern Suburbs Melbourne Local Marketing',
    seoDescription:
      'Local marketing for businesses in Melbourne’s east: Hawthorn, Camberwell, Box Hill, Doncaster, Glen Waverley and Ringwood. Get found by nearby customers.',
    h1: 'Local marketing for Melbourne’s eastern suburbs',
    cardSummary: 'Hawthorn, Camberwell, Box Hill, Doncaster, Glen Waverley, Ringwood.',
    suburbs: ['Hawthorn', 'Kew', 'Camberwell', 'Balwyn', 'Box Hill', 'Doncaster', 'Blackburn', 'Mitcham', 'Glen Waverley', 'Ringwood', 'Croydon', 'Lilydale'],
    intro: [
      'Melbourne’s east is made up of established suburbs with strong shopping centres, local strips and a lot of families and professionals who research carefully before they buy.',
      'For eastern suburbs businesses, reputation travels. A well-kept profile, genuine reviews and helpful content build the trust these customers look for.',
    ],
    landscape: [
      'Large shopping centres and busy local strips sit alongside quieter residential streets. Many residents use a mix of languages, and some search in languages other than English.',
      'Customers are often willing to travel a little further for a trusted specialist, especially for health, education and professional services.',
    ],
    searchChallenges: [
      'Competing with businesses inside major shopping centres',
      'Reaching multilingual communities with clear, accurate information',
      'Customers comparing several providers before calling',
      'Wide east–west spread from the inner east to the Yarra Ranges foothills',
    ],
    relevantServices: ['reviews', 'content', 'google-business-profile', 'email-sms'],
    commonIndustries: ['health-beauty', 'professional-services', 'property', 'retail'],
    faqs: [
      {
        q: 'Can you help us market in languages other than English?',
        a: 'We can plan for it. Translated content should be prepared or checked by a qualified translator or fluent team member — we will not publish machine translation unchecked.',
      },
      {
        q: 'Do eastern suburbs customers really read reviews?',
        a: 'Most customers everywhere check reviews before choosing a local business. Consistently asking happy customers is one of the most effective things you can do.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'south-east-bayside',
    path: '/locations/melbourne/south-east-bayside',
    name: 'South-East & Bayside',
    shortName: 'South-east & Bayside',
    tier: 'melbourne',
    parent: 'melbourne',
    seoTitle: 'South-East & Bayside Melbourne Local Marketing',
    seoDescription:
      'Local marketing for businesses from Brighton and Sandringham to Moorabbin, Dandenong and Frankston. Local SEO, reviews and ads for the south-east and bayside.',
    h1: 'Local marketing for Melbourne’s south-east and bayside',
    cardSummary: 'Brighton, Bentleigh, Cheltenham, Mordialloc, Dandenong, Frankston.',
    suburbs: ['Brighton', 'Hampton', 'Sandringham', 'Bentleigh', 'Moorabbin', 'Cheltenham', 'Mentone', 'Mordialloc', 'Oakleigh', 'Clayton', 'Dandenong', 'Frankston'],
    intro: [
      'The south-east runs from bayside villages along the beach to major industrial and manufacturing areas inland. It is one region on a map, but several very different markets.',
      'We help south-east and bayside businesses target the customers and suburbs that suit them — whether that is a bayside shopping village or a trade-heavy industrial estate.',
    ],
    landscape: [
      'Bayside suburbs have village-style shopping strips and seasonal summer activity. Inland, large commercial and industrial areas support trades, suppliers and business services.',
      'Customers along the bay often shop locally in their own village, while trade and business customers may travel across the whole region.',
    ],
    searchChallenges: [
      'Seasonal changes in demand along the bay',
      'Business-to-business searches in industrial areas',
      'Long, narrow service areas along the coastline',
      'Distinguishing neighbouring village strips',
    ],
    relevantServices: ['google-business-profile', 'local-seo', 'campaigns', 'local-ads'],
    commonIndustries: ['trades', 'hospitality', 'health-beauty', 'property'],
    faqs: [
      {
        q: 'Our demand drops in winter. Can marketing help?',
        a: 'Seasonal campaigns, email to past customers and timely offers can help smooth demand. We will not promise specific results, but we will plan around your quieter months.',
      },
      {
        q: 'We sell mainly to other businesses. Is local marketing still relevant?',
        a: 'Yes. Business buyers search locally too — for suppliers, trades and services near their site.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'western-suburbs',
    path: '/locations/melbourne/western-suburbs',
    name: 'Western Suburbs',
    shortName: 'Western suburbs',
    tier: 'melbourne',
    parent: 'melbourne',
    seoTitle: 'Western Suburbs Melbourne Local Marketing',
    seoDescription:
      'Local marketing for businesses in Melbourne’s west: Footscray, Yarraville, Williamstown, Sunshine, Point Cook and Werribee. Local SEO, profiles and ads.',
    h1: 'Local marketing for Melbourne’s western suburbs',
    cardSummary: 'Footscray, Yarraville, Williamstown, Sunshine, Point Cook, Werribee.',
    suburbs: ['Footscray', 'Seddon', 'Yarraville', 'Williamstown', 'Altona', 'Sunshine', 'St Albans', 'Deer Park', 'Laverton', 'Point Cook', 'Hoppers Crossing', 'Werribee'],
    intro: [
      'Melbourne’s west has changed quickly. Established inner-west suburbs, large logistics and industrial areas and growing residential communities all sit within a short drive of each other.',
      'Western suburbs businesses often serve a wide area. We help them show up clearly in the suburbs that matter most, without wasting effort on areas they do not serve.',
    ],
    landscape: [
      'The inner west has busy local strips and a strong food scene, while areas further out include major logistics and industrial precincts and newer housing.',
      'Communities in the west are diverse, and many businesses serve customers from a range of cultural backgrounds.',
    ],
    searchChallenges: [
      'Travel time across the region affecting which suburbs are worth targeting',
      'Rapidly growing suburbs where competition is still forming',
      'Industrial and logistics customers searching for nearby suppliers',
      'Keeping service-area settings accurate as you expand',
    ],
    relevantServices: ['local-seo', 'google-business-profile', 'local-ads', 'social-media'],
    commonIndustries: ['trades', 'hospitality', 'retail', 'health-beauty'],
    faqs: [
      {
        q: 'We are based in the west but want work in other areas. Can you help?',
        a: 'Yes. We can build service-area content and targeted ads for other regions, while being realistic that Google tends to favour businesses close to the searcher.',
      },
      {
        q: 'Is it too early to market in newer suburbs?',
        a: 'Often it is the best time. Competition in newer areas can be lower, and new residents are actively looking for local businesses.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'outer-growth-corridors',
    path: '/locations/melbourne/outer-growth-corridors',
    name: 'Outer Growth Corridors',
    shortName: 'Outer growth corridors',
    tier: 'melbourne',
    parent: 'melbourne',
    seoTitle: 'Melbourne Growth Corridors Local Marketing',
    seoDescription:
      'Local marketing for businesses in Melbourne’s growth areas: Craigieburn, Mernda, Tarneit, Melton, Clyde, Cranbourne and Pakenham. Reach new residents early.',
    h1: 'Local marketing for Melbourne’s outer growth corridors',
    cardSummary: 'Craigieburn, Mernda, Tarneit, Melton, Clyde, Cranbourne, Pakenham.',
    suburbs: ['Craigieburn', 'Mickleham', 'Mernda', 'Doreen', 'Wollert', 'Sunbury', 'Melton', 'Tarneit', 'Truganina', 'Wyndham Vale', 'Clyde North', 'Cranbourne', 'Officer', 'Pakenham'],
    intro: [
      'Melbourne’s growth corridors are full of new homes and new residents who do not yet have a favourite plumber, dentist, café or gym. They search for almost everything.',
      'Businesses that set up strong local visibility early have a real chance to become the local default as these communities grow.',
    ],
    landscape: [
      'New estates, new town centres and new schools are appearing across the north, west and south-east fringes. Many residents are young families and first home buyers.',
      'Some new areas are still being mapped, named and connected, so accurate listings and clear directions are especially important.',
    ],
    searchChallenges: [
      'New streets and estates that may not yet appear correctly in maps',
      'Residents searching by estate name as well as suburb name',
      'Large service areas with long travel times',
      'Being early without spreading your budget too thin',
    ],
    relevantServices: ['google-business-profile', 'local-seo', 'local-ads', 'campaigns'],
    commonIndustries: ['trades', 'health-beauty', 'retail', 'property'],
    faqs: [
      {
        q: 'Our suburb is new. Will Google show our business?',
        a: 'Usually, yes, but new areas can take time to be mapped correctly. We check your listing, pin location and service areas, and report map issues to Google where needed.',
      },
      {
        q: 'Should we mention estate names on our website?',
        a: 'Where customers genuinely use them, yes. We check real search behaviour before adding them.',
      },
    ],
    caseStudies: [],
    meeting: 'in_person_or_video',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'regional-victoria',
    path: '/locations/regional-victoria',
    name: 'Geelong & Regional Victoria',
    shortName: 'Regional Victoria',
    tier: 'regional_vic',
    parent: null,
    seoTitle: 'Local Marketing Geelong & Regional Victoria',
    seoDescription:
      'Local marketing for small businesses in Geelong, Ballarat, Bendigo and regional Victoria. Delivered by video, with in-person meetings by arrangement.',
    h1: 'Local marketing for Geelong and regional Victoria',
    cardSummary: 'Geelong, Surf Coast, Ballarat, Bendigo and regional towns. Video, in person by arrangement.',
    suburbs: ['Geelong', 'Bellarine Peninsula', 'Surf Coast', 'Ballarat', 'Bendigo', 'Macedon Ranges', 'Latrobe Valley', 'Shepparton', 'Warrnambool'],
    intro: [
      'Regional businesses often serve a whole town and its surrounds, plus visitors. Being the obvious local choice in Maps and search can make a big difference in a smaller market.',
      'We work with Geelong and regional Victorian businesses by video, and can meet in person by arrangement.',
    ],
    landscape: [
      'Regional centres have strong local loyalty, active community groups and, in many areas, seasonal tourism. Customers may travel from surrounding towns for the right business.',
      'Word of mouth matters, and online reviews are often word of mouth written down.',
    ],
    searchChallenges: [
      'Customers searching from surrounding towns, not just the town centre',
      'Visitors searching before they arrive',
      'Competition from Melbourne businesses advertising into the region',
      'Seasonal tourism affecting demand',
    ],
    relevantServices: ['google-business-profile', 'reviews', 'local-seo', 'social-media'],
    commonIndustries: ['hospitality', 'trades', 'retail', 'health-beauty'],
    faqs: [
      {
        q: 'Do you meet in person in regional Victoria?',
        a: 'Most work is done by video. In-person meetings can be arranged — let us know where you are and we will talk through options.',
      },
      {
        q: 'Can you help us reach tourists as well as locals?',
        a: 'Yes. We can plan content and profile updates that help visitors find you before and during their trip.',
      },
    ],
    caseStudies: [],
    meeting: 'video_in_person_by_arrangement',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
  {
    slug: 'australia',
    path: '/locations/australia',
    name: 'Australia-wide',
    shortName: 'Australia-wide',
    tier: 'remote',
    parent: null,
    seoTitle: 'Remote Local Marketing for Australian Small Businesses',
    seoDescription:
      'Remote local marketing for small businesses anywhere in Australia. Google Business Profile, local SEO, reviews and ads, delivered fully by video and online.',
    h1: 'Local marketing for small businesses across Australia',
    cardSummary: 'Fully remote local marketing, wherever your business is.',
    suburbs: [],
    intro: [
      'Local marketing does not require us to be down the road. Your customers are local; the work — your profile, website, reviews, content and ads — can be done remotely.',
      'We work with businesses outside Victoria fully by video and online, with the same process and reporting as our Melbourne clients.',
    ],
    landscape: [
      'Every town and city has its own search landscape. When we work remotely we rely on you for local knowledge, and on research tools and your data for the rest.',
      'A short kick-off call helps us understand your area, customers and competitors.',
    ],
    searchChallenges: [
      'Local knowledge we need from you to write accurate local content',
      'Time zones outside Victoria (we schedule meetings to suit)',
      'Local directories and citations that differ by state',
    ],
    relevantServices: ['google-business-profile', 'local-seo', 'reviews', 'content'],
    commonIndustries: ['professional-services', 'trades', 'health-beauty', 'retail'],
    faqs: [
      {
        q: 'Can you really do local marketing for a town you are not in?',
        a: 'Yes, with your help. The technical and content work is the same anywhere. We ask you for the local detail only you know, and we never publish local claims we cannot verify.',
      },
      {
        q: 'How do meetings work?',
        a: 'All meetings are by video at times that suit your time zone.',
      },
    ],
    caseStudies: [],
    meeting: 'remote',
    reviewStatus: 'draft-needs-review',
    needsReview: ['suburbs', 'intro', 'landscape', 'searchChallenges', 'commonIndustries', 'faqs'],
  },
];

export function getLocation(slug: string): Location | undefined {
  return locations.find((l) => l.slug === slug);
}

export const melbourneRegions = (): Location[] =>
  melbourneRegionSlugs.map((s) => getLocation(s)).filter((l): l is Location => Boolean(l));
