import type { PackageSlug } from './packages';

export interface Faq {
  q: string;
  a: string;
}

export interface Service {
  slug: string;
  name: string;
  /** schema.org serviceType */
  serviceType: string;
  seoTitle: string;
  seoDescription: string;
  cardSummary: string;
  heroTitle: string;
  heroBody: string;
  problem: string[];
  deliverables: string[];
  inclusions: { item: string; packages: PackageSlug[] | 'custom' }[];
  process: { title: string; body: string }[];
  suits: string[];
  faqs: Faq[];
  relatedPackage: PackageSlug;
  relatedIndustries: string[];
  /** Online by default. Offline = traditional/physical media; integrated = spans both. */
  channel?: 'offline' | 'integrated';
}

export type ServiceChannel = 'online' | 'offline' | 'integrated';
export const channelOf = (s: Service): ServiceChannel => s.channel ?? 'online';

export const SERVICE_GROUPS: { channel: ServiceChannel; title: string; intro: string }[] = [
  { channel: 'online', title: 'Online & social', intro: 'Google Maps, local search, reviews, your website, ads, social media and email.' },
  {
    channel: 'offline',
    title: 'Offline & traditional',
    intro: 'Print, letterbox drops, signage, vehicles, PR, local media, events, sampling and mystery shopping.',
  },
  { channel: 'integrated', title: 'Strategy, brand & campaigns', intro: 'The plan, the brand and the campaigns that tie every channel together.' },
];


export const services: Service[] = [
  {
    slug: 'local-seo',
    name: 'Local SEO',
    serviceType: 'Local search engine optimisation',
    seoTitle: 'Local SEO for Small Business',
    seoDescription:
      'Local SEO that helps nearby customers find your business in Google search and Maps. Keyword mapping, service-area pages, citations and tracking.',
    cardSummary: 'Show up when people nearby search for what you do.',
    heroTitle: 'People nearby are searching for you. Can they find you?',
    heroBody:
      'When someone searches “near me” or adds a suburb to their search, Google favours businesses with clear local signals. Local SEO builds those signals across your website, profile and listings.',
    problem: [
      'Many small business websites never say clearly where they work. Google then has to guess — and often shows a competitor who spelled it out.',
      'Local SEO fixes the basics first: what you do, where you do it, and proof that you are a real, trusted local business.',
    ],
    deliverables: [
      'Local keyword map matched to your services and service areas',
      'On-page fixes: titles, headings, local content and internal links',
      'Service-area pages written for real places you serve (no copy-paste suburb pages)',
      'LocalBusiness structured data',
      'Citation audit and clean-up',
      'Search Console and Analytics monitoring',
    ],
    inclusions: [
      { item: 'Keyword map for 1 service area', packages: ['bronze'] },
      { item: 'Keyword map for up to 3 service areas', packages: ['silver', 'gold'] },
      { item: 'Local competitor research and rank tracking', packages: ['silver', 'gold'] },
      { item: 'Local link and partnership building', packages: ['gold'] },
    ],
    process: [
      { title: 'Audit', body: 'We check your website, listings and profile for local signals and gaps.' },
      { title: 'Map', body: 'We map the searches locals use to the pages that should answer them.' },
      { title: 'Fix and build', body: 'We fix what is broken, then add useful local content each month.' },
      { title: 'Report', body: 'You get a plain-English summary of what changed and what is next.' },
    ],
    suits: [
      'Service businesses that travel to customers',
      'Shopfronts and clinics that rely on nearby foot traffic',
      'Businesses whose website says little about where they work',
    ],
    faqs: [
      {
        q: 'How long does local SEO take?',
        a: 'Most businesses see early movement within a few months, but it depends on your competition, your starting point and how much content is needed. We will not promise a timeframe we cannot control.',
      },
      {
        q: 'Do you create a page for every suburb?',
        a: 'No. Thin, copy-paste suburb pages can hurt more than help. We write pages for real service areas where you have something genuinely useful to say.',
      },
    ],
    relatedPackage: 'bronze',
    relatedIndustries: ['trades', 'professional-services', 'health-beauty'],
  },
  {
    slug: 'google-business-profile',
    name: 'Google Business Profile',
    serviceType: 'Google Business Profile management',
    seoTitle: 'Google Business Profile Optimisation',
    seoDescription:
      'Google Business Profile set-up and optimisation: categories, services, service areas, photos, posts and Q&A, managed every month.',
    cardSummary: 'Make your Maps listing complete, accurate and active.',
    heroTitle: 'Your Google Business Profile is often the first thing locals see.',
    heroBody:
      'Before anyone visits your website, they see your profile in Maps: your reviews, photos, hours and services. An incomplete profile quietly sends customers elsewhere.',
    problem: [
      'Wrong categories, missing services, old photos and unanswered questions all make a profile look neglected.',
      'We set it up properly, keep it active with regular posts, and watch it for unwanted edits.',
    ],
    deliverables: [
      'Primary and secondary category review',
      'Services, products and service areas written out in full',
      'Hours, holiday hours and attributes kept up to date',
      'Photo plan and uploads',
      'Regular Google Business Profile posts',
      'Q&A seeding and monitoring',
      'Monthly insights summary',
    ],
    inclusions: [
      { item: 'Profile optimisation and 4 posts per month', packages: ['bronze', 'silver', 'gold'] },
      { item: 'Up to 3 profile locations', packages: ['gold'] },
      { item: '4+ locations', packages: 'custom' },
    ],
    process: [
      { title: 'Access', body: 'We are added as a manager — you always stay the owner of your profile.' },
      { title: 'Optimise', body: 'We complete every relevant section and fix inconsistencies.' },
      { title: 'Keep active', body: 'Posts, photos and answers go up every month.' },
      { title: 'Monitor', body: 'We watch insights and suggested edits and let you know what changes.' },
    ],
    suits: [
      'Businesses that have never touched their profile since creating it',
      'Service-area businesses that hide their address',
      'Businesses with more than one location',
    ],
    faqs: [
      {
        q: 'Will you own my Google Business Profile?',
        a: 'No. You remain the owner. We ask to be added as a manager so you keep full control.',
      },
      {
        q: 'I work from home and do not want my address shown. Is that a problem?',
        a: 'Not at all. Google allows service-area businesses to hide their address and show the areas they serve instead. We set that up correctly.',
      },
    ],
    relatedPackage: 'bronze',
    relatedIndustries: ['trades', 'hospitality', 'health-beauty'],
  },
  {
    slug: 'reviews',
    name: 'Reviews & Reputation',
    serviceType: 'Online review generation and reputation management',
    seoTitle: 'Google Review Generation & Reputation Management',
    seoDescription:
      'Get more genuine Google reviews and respond well to every one. Review request set-up, response drafting and reputation monitoring for local businesses.',
    cardSummary: 'More genuine reviews, and thoughtful replies to every one.',
    heroTitle: 'Locals check your reviews before they call.',
    heroBody:
      'Happy customers rarely leave a review unless someone asks. We make asking simple and consistent, and help you reply to every review — good or bad — in your own voice.',
    problem: [
      'A handful of old reviews next to a competitor with recent ones is an easy decision for a customer.',
      'We set up a simple, compliant way to ask every happy customer, and draft replies so none go unanswered.',
    ],
    deliverables: [
      'Review request links, QR codes and message templates',
      'Timing and process advice for your team',
      'Review response drafting',
      'Reputation monitoring and alerts (Gold)',
      'Guidance that keeps you within Google’s review policies — no fake or incentivised reviews',
    ],
    inclusions: [
      { item: 'Review-generation set-up and response drafting', packages: ['bronze', 'silver', 'gold'] },
      { item: 'Review program and reputation monitoring', packages: ['gold'] },
    ],
    process: [
      { title: 'Set up', body: 'We create your review links, templates and QR codes.' },
      { title: 'Train', body: 'We show your team when and how to ask.' },
      { title: 'Respond', body: 'We draft replies for you to approve or post.' },
      { title: 'Review', body: 'We report on review volume and themes each month.' },
    ],
    suits: [
      'Businesses with great service but few online reviews',
      'Businesses that have received a tough review and want to respond well',
      'Multi-location businesses that need consistency',
    ],
    faqs: [
      {
        q: 'Can you remove negative reviews?',
        a: 'Only Google can remove reviews, and only if they break Google’s policies. We can help you flag reviews that genuinely breach policy and write calm, professional replies to the rest.',
      },
      {
        q: 'Can we offer a discount for a review?',
        a: 'No. Incentivised reviews breach Google’s policies and can mislead customers. We only use honest, compliant ways to ask.',
      },
    ],
    relatedPackage: 'bronze',
    relatedIndustries: ['hospitality', 'health-beauty', 'trades'],
  },
  {
    slug: 'websites',
    name: 'Websites',
    serviceType: 'Small business website design and updates',
    seoTitle: 'Small Business Websites Built for Local Search',
    seoDescription:
      'Fast, mobile-friendly small business websites with clear calls to action, local structured data and service-area pages. Updates and rebuilds.',
    cardSummary: 'A fast, clear website that turns local visitors into enquiries.',
    heroTitle: 'Most local customers find you on their phone.',
    heroBody:
      'If your website is slow, hard to read on mobile or hides your phone number, people leave. We build and update websites that load quickly and make it easy to call, book or buy.',
    problem: [
      'Old websites often miss the basics: a clickable phone number, clear service areas, fast mobile loading and structured data.',
      'We fix those basics on your current site or, where it makes sense, scope a rebuild.',
    ],
    deliverables: [
      'Website local SEO check',
      'Mobile speed and usability fixes',
      'Click-to-call, booking and enquiry form set-up',
      'LocalBusiness and Service structured data',
      'Service and service-area page templates',
      'Minor monthly updates (Gold) or full rebuilds (custom quote)',
    ],
    inclusions: [
      { item: 'Website local SEO check', packages: ['bronze', 'silver', 'gold'] },
      { item: 'Up to 2 hours per month of minor updates', packages: ['gold'] },
      { item: 'Website rebuilds and eCommerce', packages: 'custom' },
    ],
    process: [
      { title: 'Check', body: 'We review speed, mobile usability and local signals.' },
      { title: 'Plan', body: 'We agree fixes or a rebuild scope in writing.' },
      { title: 'Build', body: 'We make the changes on a staging copy first.' },
      { title: 'Launch', body: 'We go live, check tracking and hand over.' },
    ],
    suits: [
      'Businesses with a slow or dated website',
      'Businesses whose site does not work well on mobile',
      'Anyone planning a rebuild who wants to keep their Google visibility',
    ],
    faqs: [
      {
        q: 'Will a new website hurt my Google rankings?',
        a: 'It can if it is launched carelessly. We plan redirects, keep good content and check Search Console after launch to protect your visibility.',
      },
      {
        q: 'Do you work with my current website platform?',
        a: 'Usually, yes. We will confirm after the website check whether updating your current site or rebuilding makes more sense.',
      },
    ],
    relatedPackage: 'gold',
    relatedIndustries: ['professional-services', 'retail', 'property'],
  },
  {
    slug: 'local-ads',
    name: 'Local Ads',
    serviceType: 'Local Google Ads and Meta Ads management',
    seoTitle: 'Local Google Ads & Meta Ads Management',
    seoDescription:
      'Locally targeted Google Ads, Local Services Ads (where eligible) and Meta Ads for small businesses. Clear set-up, conversion tracking and honest reporting.',
    cardSummary: 'Ads that reach people in the areas you actually serve.',
    heroTitle: 'Paying for clicks from people you cannot serve?',
    heroBody:
      'Poorly targeted ads waste budget on the wrong suburbs, the wrong searches and the wrong times. We set up local campaigns that focus spend on the areas and customers you want.',
    problem: [
      'Many small business ad accounts run on broad settings that show ads well outside the service area.',
      'We tighten targeting, track calls and forms, and report in plain English on what the spend is doing.',
    ],
    deliverables: [
      'Local Google Ads campaign set-up',
      'Location, schedule and keyword targeting',
      'Local Services Ads (where your category is eligible)',
      'Local Meta (Facebook and Instagram) ads',
      'Call, form, booking and directions conversion tracking',
      'Monthly performance reporting',
    ],
    inclusions: [
      { item: 'Local Google Ads set-up (management optional)', packages: ['silver'] },
      { item: 'Google Ads and Local Services Ads management', packages: ['gold'] },
      { item: 'Local Meta Ads management', packages: ['gold'] },
      { item: 'Larger multi-region budgets', packages: 'custom' },
    ],
    process: [
      { title: 'Plan', body: 'We agree areas, services, budget and what a good lead looks like.' },
      { title: 'Track', body: 'We set up conversion tracking before spending a dollar.' },
      { title: 'Launch', body: 'Campaigns go live with tight local targeting.' },
      { title: 'Refine', body: 'We adjust monthly and explain what changed and why.' },
    ],
    suits: [
      'Businesses that need enquiries sooner than SEO can deliver',
      'Seasonal businesses and promotions',
      'Anyone unsure whether their current ads are working',
    ],
    faqs: [
      {
        q: 'How much should I spend on ads?',
        a: 'It depends on your industry, area and goals. We will recommend a starting budget and explain the trade-offs. Ad spend is always separate from our fee and paid directly by you.',
      },
      {
        q: 'Who owns the ad account?',
        a: 'You do. We work inside an account in your name so the history and data stay with your business.',
      },
    ],
    relatedPackage: 'gold',
    relatedIndustries: ['trades', 'property', 'health-beauty'],
  },
  {
    slug: 'social-media',
    name: 'Social Media',
    serviceType: 'Local social media management',
    seoTitle: 'Local Social Media Management for Small Business',
    seoDescription:
      'Regular, locally relevant social posts on Facebook, Instagram and LinkedIn that show your community you are open, active and trusted.',
    cardSummary: 'Stay visible in your community’s feeds, without the time drain.',
    heroTitle: 'Your social pages are proof you are open for business.',
    heroBody:
      'Customers often check Facebook or Instagram to see if a business is active and trustworthy. We keep your pages current with posts that sound like you and speak to your local area.',
    problem: [
      'Posting consistently is hard when you are busy running the business, so pages go quiet for months.',
      'We plan, write and schedule posts that reflect your work and your community.',
    ],
    deliverables: [
      'Monthly content calendar',
      'Post copy and image selection',
      'Scheduling on Facebook, Instagram and LinkedIn (where appropriate)',
      'Local events and seasonal hooks',
      'Monthly engagement summary',
    ],
    inclusions: [
      { item: '2 posts per month', packages: ['bronze'] },
      { item: '8 posts per month on Facebook and Instagram', packages: ['silver'] },
      { item: '12 posts per month including LinkedIn', packages: ['gold'] },
    ],
    process: [
      { title: 'Plan', body: 'We agree themes and a monthly calendar with you.' },
      { title: 'Create', body: 'We write posts and choose or request photos.' },
      { title: 'Approve', body: 'You approve before anything is published.' },
      { title: 'Publish', body: 'We schedule posts and report on engagement.' },
    ],
    suits: [
      'Businesses whose pages have gone quiet',
      'Hospitality and retail businesses with regular news',
      'Professional services building local trust',
    ],
    faqs: [
      {
        q: 'Do we need to supply photos?',
        a: 'Real photos of your team and work perform best, so we will ask for some. We can supplement with suitable licensed images where needed.',
      },
      {
        q: 'Do you reply to comments and messages?',
        a: 'Community management can be added. By default we publish and report; you or your team handle customer messages.',
      },
    ],
    relatedPackage: 'silver',
    relatedIndustries: ['hospitality', 'retail', 'health-beauty'],
  },
  {
    slug: 'content',
    name: 'Content & Copywriting',
    serviceType: 'Copywriting and local content writing',
    seoTitle: 'Copywriting & Local Content for Small Business',
    seoDescription:
      'Copywriting for your website, social, press releases, print and advertising, plus useful local articles and service-area pages published every month.',
    cardSummary: 'Website, social, print, advertising and PR copy, plus local content.',
    heroTitle: 'Customers have questions. Your website should answer them.',
    heroBody:
      'Good local content explains what you do, where you do it and what customers should expect. It helps people decide, and gives search engines — including AI search — clear answers to use.',
    problem: [
      'Thin pages with the same text and a swapped suburb name do not help anyone.',
      'We write genuinely useful content for the areas and services that matter most to your business.',
    ],
    deliverables: [
      'Copywriting for websites, social media, press releases, print and advertising',
      'Speeches, presentations and internal communications',
      'Monthly content plan based on your keyword map',
      'Service pages and service-area pages',
      'Local guides and FAQs',
      'Updates to existing pages that have gone stale',
      'Internal linking between services, locations and case studies',
    ],
    inclusions: [
      { item: '1 article or page update per month', packages: ['bronze'] },
      { item: '2 local content pieces per month', packages: ['silver'] },
      { item: '4 local content or SEO assets per month', packages: ['gold'] },
    ],
    process: [
      { title: 'Plan', body: 'We choose topics based on real local searches and your goals.' },
      { title: 'Interview', body: 'A short chat with you gives us the local detail only you know.' },
      { title: 'Write', body: 'We write in plain Australian English, in your voice.' },
      { title: 'Publish', body: 'We publish, link it in and monitor how it performs.' },
    ],
    suits: [
      'Businesses with little content on their website',
      'Businesses serving several distinct areas',
      'Anyone who wants to be ready for AI-powered search answers',
    ],
    faqs: [
      {
        q: 'Do you use AI to write content?',
        a: 'We may use tools to help research and draft, but every piece is edited by a person and checked with you for accuracy. We never publish local claims we cannot back up.',
      },
      {
        q: 'Who owns the content?',
        a: 'You do, once it is paid for. It lives on your website.',
      },
    ],
    relatedPackage: 'silver',
    relatedIndustries: ['professional-services', 'property', 'trades'],
  },
  {
    slug: 'email-sms',
    name: 'Email & SMS',
    serviceType: 'Email and SMS marketing',
    seoTitle: 'Email & SMS Marketing for Local Business',
    seoDescription:
      'Spam Act-compliant email and SMS campaigns that bring past customers back: reminders, offers, news and review requests.',
    cardSummary: 'Bring past customers back with timely, compliant messages.',
    heroTitle: 'Your past customers are your easiest next sale.',
    heroBody:
      'People who have bought from you before are the most likely to buy again — if they remember you. Regular, useful emails and texts keep you front of mind.',
    problem: [
      'Customer lists often sit unused in a spreadsheet or booking system.',
      'We turn them into simple, compliant campaigns with clear consent and easy unsubscribes.',
    ],
    deliverables: [
      'Email or SMS campaign planning',
      'Copywriting and design',
      'List hygiene and consent checks (Spam Act 2003)',
      'Scheduling and sending through your platform',
      'Results summary',
    ],
    inclusions: [
      { item: '1 email or SMS campaign per month', packages: ['silver'] },
      { item: '2 email or SMS campaigns per month', packages: ['gold'] },
    ],
    process: [
      { title: 'Check consent', body: 'We confirm your list was collected with consent.' },
      { title: 'Plan', body: 'We agree the message, offer and timing.' },
      { title: 'Create', body: 'We write and design the campaign for your approval.' },
      { title: 'Send and review', body: 'We send, then report on opens, clicks and replies.' },
    ],
    suits: [
      'Businesses with repeat or seasonal customers',
      'Clinics and salons with appointment reminders',
      'Retailers and hospitality venues with regular offers',
    ],
    faqs: [
      {
        q: 'Can we email people who have not opted in?',
        a: 'Under the Spam Act 2003 you generally need consent to send commercial messages, and every message must identify you and include an easy way to unsubscribe. We will help you get this right.',
      },
      {
        q: 'Which platform do you use?',
        a: 'We work with common platforms such as the one you already use. If you do not have one, we will recommend a suitable option.',
      },
    ],
    relatedPackage: 'silver',
    relatedIndustries: ['health-beauty', 'retail', 'hospitality'],
  },
  {
    slug: 'strategy',
    channel: 'integrated',
    name: 'Marketing Strategy & Planning',
    serviceType: 'Marketing strategy consulting and annual planning',
    seoTitle: 'Marketing Strategy & Annual Marketing Plans',
    seoDescription:
      'A clear marketing road map for your business: target market, strengths, goals and a practical annual plan of dates, events, activities and channels, online and offline.',
    cardSummary: 'A clear road map: target market, goals and a 12-month plan.',
    heroTitle: 'Know exactly what to do next, and why.',
    heroBody:
      'We want to understand your business, so we spend enough time together to get to know your strengths, weaknesses, long-term goals and short-term objectives. Then we turn that into a clear marketing plan you can follow, like a road map.',
    problem: [
      'Without a plan, marketing becomes a series of one-off decisions: a flyer here, a boosted post there, with no way of knowing what is working.',
      'Strategic consultation means working closely with you to identify your target market, strengths, weaknesses and goals, then building an annual plan of key dates, events, activities and opportunities, online and offline, so your marketing spend works towards your goals.',
    ],
    deliverables: [
      'Discovery workshop: your business, customers, competitors and goals',
      'Target market and positioning',
      'Channel mix across online, print, outdoor, media and events',
      '12-month marketing calendar of key dates, events and activities',
      'Budget guidance and measures of success',
      'Quarterly reviews to adjust the plan',
    ],
    inclusions: [
      { item: 'Quarterly review', packages: ['bronze'] },
      { item: 'Monthly strategy meeting and quarterly campaign planning', packages: ['silver', 'gold'] },
      { item: 'Standalone strategy workshop and annual plan', packages: 'custom' },
    ],
    process: [
      { title: 'Listen', body: 'We spend time getting to know your business, market and goals.' },
      { title: 'Analyse', body: 'We look at your customers, competitors, strengths and gaps.' },
      { title: 'Plan', body: 'We map a 12-month calendar across the channels that suit you.' },
      { title: 'Review', body: 'We check progress quarterly and adjust.' },
    ],
    suits: [
      'Businesses spending on marketing without a clear plan',
      'New businesses and new product launches',
      'Retailers planning around seasons, events and key trading dates',
    ],
    faqs: [
      {
        q: 'Do I need a strategy before I start a package?',
        a: 'Not necessarily. Every package starts with a short discovery. A standalone strategy and annual plan suits businesses that want the full road map first.',
      },
      {
        q: 'Will the plan include offline marketing?',
        a: 'Yes. We plan across online and offline channels, including search, social, email, print, signage, local media and events, based on where your customers actually are.',
      },
    ],
    relatedPackage: 'silver',
    relatedIndustries: ['retail', 'professional-services', 'hospitality'],
  },
  {
    slug: 'branding',
    channel: 'integrated',
    name: 'Branding',
    serviceType: 'Small business branding',
    seoTitle: 'Branding for Local Small Business',
    seoDescription:
      'Practical branding for small businesses: a clear message, consistent look and wording that works on your profile, website, signage and social.',
    cardSummary: 'A clear, consistent brand that locals recognise and remember.',
    heroTitle: 'Locals should recognise you at a glance.',
    heroBody:
      'Your van, shopfront, website and Google profile should all look and sound like the same business. Consistent branding builds recognition and trust in your area.',
    problem: [
      'Do you have a great product or service, but aren’t sure how to turn it into a recognisable brand? Identity, positioning and consistency are crucial to being competitive.',
      'Mismatched logos, colours and wording across your shopfront, vehicles, print, listings and social make a business look less established. We develop a consistent brand that works everywhere locals see you, online and offline.',
    ],
    deliverables: [
      'Brand message and positioning statement',
      'Logo refresh or clean-up (where needed)',
      'Colour palette and type guidance',
      'Consistent business description for listings',
      'Templates for social posts and signage',
    ],
    inclusions: [
      { item: 'Consistent business descriptions across listings', packages: ['bronze', 'silver', 'gold'] },
      { item: 'Brand refresh and templates', packages: 'custom' },
    ],
    process: [
      { title: 'Listen', body: 'We learn what makes your business different.' },
      { title: 'Define', body: 'We write a clear message and agree the look.' },
      { title: 'Apply', body: 'We roll it out across your profile, site and social.' },
      { title: 'Guide', body: 'You get a simple guide to keep it consistent.' },
    ],
    suits: [
      'New businesses getting set up',
      'Established businesses that have outgrown a DIY logo',
      'Businesses merging or adding locations',
    ],
    faqs: [
      {
        q: 'Do we need a full rebrand?',
        a: 'Usually not. Most small businesses benefit more from making what they already have consistent. We will tell you honestly if a bigger change is worth it.',
      },
      {
        q: 'Is branding included in the packages?',
        a: 'Consistent listing descriptions are included. Logo and brand refresh work is quoted separately.',
      },
    ],
    relatedPackage: 'bronze',
    relatedIndustries: ['retail', 'hospitality', 'professional-services'],
  },
  {
    slug: 'campaigns',
    channel: 'integrated',
    name: 'Sales Promotions & Campaigns',
    serviceType: 'Sales promotion and local campaign development',
    seoTitle: 'Local Marketing Campaigns for Small Business',
    seoDescription:
      'Planned local campaigns that combine your profile, social, email, ads and community to promote an offer, opening, event or season.',
    cardSummary: 'Planned campaigns for openings, offers, events and seasons.',
    heroTitle: 'Got something to promote locally? Make it count.',
    heroBody:
      'A new location, a seasonal offer or a community event deserves more than one social post. We plan campaigns that use every local channel together.',
    problem: [
      'We tailor campaigns to your business objectives, whether that is as big-picture as a year-on-year increase in category sales or as specific as more enquiries from one suburb over one month. We develop short, sharp promotions or annual campaigns to reach your goals.',
      'One-off promotions often go out on a single channel and are quickly forgotten. We coordinate your profile, website, social, email, ads, print, in-store material and local media so the message reaches locals several times.',
    ],
    deliverables: [
      'Campaign plan with goals and timing',
      'Offer and messaging',
      'Coordinated posts, emails and ads',
      'Landing page or website update',
      'Results summary and learnings',
    ],
    inclusions: [
      { item: 'Quarterly local campaign planning', packages: ['silver'] },
      { item: '1 local campaign per month', packages: ['gold'] },
    ],
    process: [
      { title: 'Brief', body: 'We agree what you are promoting, to whom and why.' },
      { title: 'Plan', body: 'We choose channels and a schedule.' },
      { title: 'Run', body: 'We create and launch across channels.' },
      { title: 'Learn', body: 'We report on results and what to repeat.' },
    ],
    suits: [
      'New openings and relocations',
      'Seasonal businesses',
      'Businesses taking part in local events',
    ],
    faqs: [
      {
        q: 'Can you help with a single campaign?',
        a: 'Campaigns are included in Silver (planning) and Gold (monthly). One-off campaigns can be quoted separately.',
      },
      {
        q: 'Do you organise events?',
        a: 'We plan the marketing around an event. Event logistics are handled by you or your event partners.',
      },
    ],
    relatedPackage: 'gold',
    relatedIndustries: ['hospitality', 'retail', 'property'],
  },

  {
    slug: 'print-direct-mail',
    channel: 'offline',
    name: 'Print & Direct Mail',
    serviceType: 'Print marketing and direct mail',
    seoTitle: 'Print Marketing, Flyers & Letterbox Drops',
    seoDescription:
      'Flyers, brochures, postcards, catalogues and letterbox drops that reach households in your area, designed, printed and tracked so you can see what works.',
    cardSummary: 'Flyers, brochures, postcards and letterbox drops for your streets.',
    heroTitle: 'Some of your best customers still check the letterbox.',
    heroBody:
      'A well-designed flyer or postcard, dropped in the right streets at the right time, puts your business on the fridge and top of mind. We plan, design, print and distribute local print that looks professional and can be measured.',
    problem: [
      'Print often gets done in a rush: a cluttered design, the wrong streets and no way of telling whether it worked.',
      'We treat print like any other channel. We start with a clear offer and a defined area, then track responses with QR codes, offer codes and dedicated phone numbers.',
    ],
    deliverables: [
      'Flyer, brochure, postcard and catalogue design',
      'Letterbox drops and addressed direct mail planned by suburb and street',
      'Business cards, menus, price lists and stationery',
      'Point-of-sale material, shelf talkers and counter cards',
      'Print buying and proofing with trusted suppliers',
      'Response tracking with QR codes, offer codes and call tracking',
    ],
    inclusions: [
      { item: 'Print design as part of a monthly local campaign', packages: ['gold'] },
      { item: 'Letterbox drops, direct mail and print production', packages: 'custom' },
    ],
    process: [
      { title: 'Target', body: 'We choose the suburbs, streets or customer list to reach.' },
      { title: 'Design', body: 'One clear message, a strong offer and a way to respond.' },
      { title: 'Print & deliver', body: 'We manage proofs, printing and distribution for you.' },
      { title: 'Measure', body: 'We count scans, codes and calls so you know what came back.' },
    ],
    suits: [
      'Trades and home services working in defined suburbs',
      'Cafés, restaurants and retailers launching offers',
      'Real estate agents, clinics and service businesses building local awareness',
    ],
    faqs: [
      {
        q: 'Does letterbox marketing still work?',
        a: 'It can work well for local businesses when the design is clear, the offer is relevant and the area is well chosen. We track responses so you can judge it on results rather than guesswork.',
      },
      {
        q: 'Are printing and distribution costs included?',
        a: 'No. Like ad spend, printing and distribution costs are quoted up front and billed at cost or as agreed. Our fee covers planning, design and management.',
      },
      {
        q: 'Can you respect "No junk mail" signs?',
        a: 'Yes. Unaddressed drops should always respect "No junk mail" and "No advertising material" signs, and we brief distributors to do so.',
      },
    ],
    relatedPackage: 'gold',
    relatedIndustries: ['trades', 'property', 'hospitality', 'retail'],
  },
  {
    slug: 'signage-outdoor',
    channel: 'offline',
    name: 'Signage, Vehicle Graphics & Outdoor',
    serviceType: 'Signage and outdoor advertising',
    seoTitle: 'Shop Signage, Vehicle Graphics & Outdoor Advertising',
    seoDescription:
      'Shopfront signage, window graphics, A-frames, vehicle graphics, site signs, banners and billboards that make your business easy to spot and remember locally.',
    cardSummary: 'Shopfronts, windows, vehicles, site signs, banners and billboards.',
    heroTitle: 'If locals drive past you every day, make sure they notice.',
    heroBody:
      'Your shopfront, van and job-site signs are seen by the same local people again and again. Clear, consistent signage turns that daily exposure into recognition, and makes it easy to find you when someone needs you.',
    problem: [
      'Faded signs, cluttered windows and unbranded vehicles waste some of the most valuable local exposure you have.',
      'We design signage that matches your brand, your Google Business Profile and your website, so people recognise you wherever they see you.',
    ],
    deliverables: [
      'Shopfront, fascia and window signage design',
      'A-frames, flags, banners and event signage',
      'Vehicle graphics and fleet branding',
      'Job-site and project signs for trades and builders',
      'Billboard, bus-shelter and local outdoor placements (where available)',
      'Coordination with sign writers and installers, including council permit checks',
    ],
    inclusions: [
      { item: 'Consistent branding across signage and listings', packages: ['bronze', 'silver', 'gold'] },
      { item: 'Signage design, production and outdoor placements', packages: 'custom' },
    ],
    process: [
      { title: 'Audit', body: 'We look at where locals see you now: shopfront, vehicles and sites.' },
      { title: 'Design', body: 'Legible at a glance, on brand, with your key message and contact details.' },
      { title: 'Produce', body: 'We brief and manage sign writers, printers and installers.' },
      { title: 'Connect', body: 'We match your signage to your Maps listing and website so it all adds up.' },
    ],
    suits: [
      'Tradies and service businesses with vans and utes on the road',
      'Shops, cafés and clinics on busy streets',
      'Builders and developers with active job sites',
    ],
    faqs: [
      {
        q: 'Do I need council approval for signage?',
        a: 'Often, yes. Rules vary by council and sign type. We check the requirements with your sign supplier before anything is produced.',
      },
      {
        q: 'Is signage production included in a package?',
        a: 'Design direction and consistency are covered by our packages. Production, installation and outdoor media are quoted separately.',
      },
    ],
    relatedPackage: 'silver',
    relatedIndustries: ['trades', 'retail', 'hospitality', 'property'],
  },
  {
    slug: 'public-relations',
    channel: 'offline',
    name: 'Public Relations & Local Media',
    serviceType: 'Public relations and local media advertising',
    seoTitle: 'Public Relations, Local Press & Radio Advertising',
    seoDescription:
      'Big Cat PR: media releases, launches, events and photo opportunities, plus advertising in local newspapers, community radio, magazines and newsletters.',
    cardSummary: 'Big Cat PR, media launches, local papers, radio and newsletters.',
    heroTitle: 'Your community has its own media. Be part of it.',
    heroBody:
      'Local newspapers, community radio, council and school newsletters and sports club programs reach people who care about their area. We help you choose the right outlets, write the right message and get a genuine local story in front of them.',
    problem: [
      'Gaining PR coverage in relevant publications is an inexpensive and more credible way of promoting your offering than traditional print advertising. Big Cat PR finds the right media for you and develops the creative, stunts, events, media and public launches and photo opportunities that get publicity where it counts.',
      'Local media can be good value, but it is easy to buy space in the wrong outlet or run an advert nobody responds to.',
      'We pick outlets that reach your service area and write adverts and media releases with a clear response path, then track the results.',
    ],
    deliverables: [
      'Local media planning: newspapers, magazines, community radio and podcasts',
      'Print advert and radio script writing',
      'Media releases and local story pitching (no guaranteed coverage)',
      'Launches, publicity stunts, events and photo opportunities',
      'School, club, church and community newsletter placements',
      'Advertorial and directory listings in local publications',
      'Response tracking with offer codes, landing pages and call tracking',
    ],
    inclusions: [
      { item: 'Local media ideas in quarterly campaign planning', packages: ['silver', 'gold'] },
      { item: 'Media buying, radio production and PR campaigns', packages: 'custom' },
    ],
    process: [
      { title: 'Plan', body: 'We shortlist outlets that genuinely reach your customers.' },
      { title: 'Create', body: 'We write the advert, script or media release for your approval.' },
      { title: 'Book', body: 'We book space or airtime at agreed rates. Media costs are separate.' },
      { title: 'Track', body: 'We measure responses and recommend whether to repeat.' },
    ],
    suits: [
      'Businesses serving an established local community',
      'Regional businesses where local media still has strong reach',
      'New openings, relocations and milestones with a genuine local story',
    ],
    faqs: [
      {
        q: 'Can you guarantee newspaper or radio coverage?',
        a: 'No. Paid advertising is booked, but editorial coverage is always the outlet’s decision. We write strong, genuine local stories to give you the best chance.',
      },
      {
        q: 'Is media spend included?',
        a: 'No. Advertising space and airtime are paid separately and agreed with you before booking.',
      },
    ],
    relatedPackage: 'silver',
    relatedIndustries: ['health-beauty', 'professional-services', 'hospitality', 'retail'],
  },
  {
    slug: 'events-experiential',
    channel: 'offline',
    name: 'Events, Experiential & Sponsorships',
    serviceType: 'Experiential marketing, events, sponsorship and promotional products',
    seoTitle: 'Experiential Marketing, Events & Local Sponsorships',
    seoDescription:
      'Product sampling, in-store activations, market stalls, expos, open days, local sponsorships and branded merchandise that put your brand face to face with your community.',
    cardSummary: 'Sampling, in-store activations, events, sponsorships and merch.',
    heroTitle: 'Nothing builds local trust like meeting people face to face.',
    heroBody:
      'Community events, market stalls, open days and local sponsorships let people meet you, not just read about you. We plan how you show up, what you give away and how you follow up, so the goodwill turns into customers.',
    problem: [
      'Sampling, product testing and product placement are proven ways to get your product noticed and into the hearts and minds of your audience. But activations, sponsorships and event stalls often come down to a banner and a pile of brochures, with no follow-up.',
      'We plan the whole thing: the right events, a stand people want to visit, a reason to leave their details (with consent) and follow-up afterwards.',
    ],
    deliverables: [
      'Product sampling, demonstrations and product testing',
      'In-store activations and product placement for retail brands',
      'Event and market selection for your area',
      'Stand design: banners, displays, brochures and giveaways',
      'Open days, workshops and customer events',
      'Local sports club, school and community sponsorship planning',
      'Branded promotional products and merchandise',
      'Lead capture with consent, and post-event email or SMS follow-up',
    ],
    inclusions: [
      { item: 'Event promotion as part of a monthly local campaign', packages: ['gold'] },
      { item: 'Event management, sponsorship and merchandise', packages: 'custom' },
    ],
    process: [
      { title: 'Choose', body: 'We help you pick events and sponsorships your customers actually attend.' },
      { title: 'Prepare', body: 'Stand, materials, offer and a simple way to capture interest.' },
      { title: 'Promote', body: 'We tell your followers, email list and local media you will be there.' },
      { title: 'Follow up', body: 'We turn contacts into conversations and measure what it delivered.' },
    ],
    suits: [
      'Retail and consumer brands launching or growing a product',
      'Businesses that sell better face to face',
      'Health, fitness and wellness businesses running open days or workshops',
      'Businesses sponsoring local sports clubs, schools or charities',
    ],
    faqs: [
      {
        q: 'Is sponsorship worth it for a small business?',
        a: 'It can be, when the club or event genuinely reaches your customers and you activate it properly, with signage, offers and follow-up, rather than just paying for a logo.',
      },
      {
        q: 'Are event fees and merchandise included?',
        a: 'No. Stall fees, sponsorship amounts and merchandise are paid separately and agreed with you first.',
      },
    ],
    relatedPackage: 'gold',
    relatedIndustries: ['health-beauty', 'hospitality', 'retail', 'professional-services'],
  },
  {
    slug: 'mystery-shopping',
    channel: 'offline',
    name: 'Mystery Shopping & Customer Experience',
    serviceType: 'Mystery shopping and customer experience research',
    seoTitle: 'Mystery Shopping & Customer Experience Audits',
    seoDescription:
      'Find out where you stand before you spend more on marketing. Mystery shopping by phone, online and face to face for retail and corporate businesses.',
    cardSummary: 'See your business the way customers do: phone, online and in store.',
    heroTitle: 'Know where you stand before you spend more on marketing.',
    heroBody:
      'Mystery shopping measures what customers really experience, from the first phone call to the website to face-to-face service. Another pair of eyes and ears can be very useful, and it is amazing how much you can learn.',
    problem: [
      'There is little point driving more people to your business if the phone goes unanswered, the website is confusing or the in-store experience lets you down.',
      'Mystery shopping works in both retail and corporate settings. It measures key performance indicators and overall customer and client satisfaction, then reports the findings so you can see your strengths and fix your weaknesses.',
    ],
    deliverables: [
      'Mystery shopping by phone, online and face to face',
      'Retail and corporate customer journey audits',
      'Competitor comparison shops (where appropriate)',
      'Scorecards against the standards you set',
      'Findings report with practical recommendations',
      'Repeat audits to track improvement',
    ],
    inclusions: [{ item: 'Mystery shopping programs and customer experience audits', packages: 'custom' }],
    process: [
      { title: 'Define', body: 'We agree what good looks like: your service standards and KPIs.' },
      { title: 'Shop', body: 'Trained shoppers contact you by phone, online and in person.' },
      { title: 'Report', body: 'You get clear findings, examples and priorities.' },
      { title: 'Improve', body: 'We help you act on the results and re-measure.' },
    ],
    suits: [
      'Retailers with one or more stores',
      'Businesses that rely on phone enquiries converting to bookings',
      'Multi-location businesses wanting consistent service',
    ],
    faqs: [
      {
        q: 'Will my staff know they are being mystery shopped?',
        a: 'That is your choice. Many businesses tell staff that shopping happens from time to time, which encourages consistent service without singling anyone out.',
      },
      {
        q: 'Is this only for retail?',
        a: 'No. We shop retail stores, clinics, trades, professional services and corporate businesses, by phone, online and face to face.',
      },
    ],
    relatedPackage: 'gold',
    relatedIndustries: ['retail', 'hospitality', 'health-beauty', 'professional-services'],
  },
];

export function getService(slug: string): Service | undefined {
  return services.find((s) => s.slug === slug);
}
