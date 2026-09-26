import { business } from '../data/business';
import { packages, customPackage } from '../data/packages';
import { services } from '../data/services';
import { industries } from '../data/industries';
import { locations } from '../data/locations';
import { caseStudies } from '../data/caseStudies';
import { CHECKUP_CTA, CHECKUP_PATH, PACKAGES_CTA } from '../constants';
import { CardGrid, ClosingCta, ImagePlaceholder, PackageCard, Section } from '../components/Blocks';
import { CaseStudyList } from './shared';

export default function Home() {
  return (
    <>
      <section className="hero" aria-labelledby="hero-heading">
        <div className="container hero-grid">
          <div className="hero-copy">
            <p className="eyebrow">{business.tagline}</p>
            <h1 id="hero-heading">Get found by the customers near you.</h1>
            <p className="hero-body">
              Big Cat Marketing is Melbourne&apos;s local marketing team for small business. We help you show up on Google Maps, in
              local search and across your community — so more people nearby call, book and buy.
            </p>
            <div className="actions">
              <a className="btn btn-primary btn-lg" href={CHECKUP_PATH} data-cta="checkup_hero">
                {CHECKUP_CTA}
              </a>
              <a className="btn btn-ghost btn-lg" href="/packages" data-cta="packages_hero">
                {PACKAGES_CTA}
              </a>
            </div>
            <p className="trust-line">{business.serviceAreaLine}</p>
          </div>
          <div className="hero-media">
            <ImagePlaceholder label="Melbourne small-business owner at their shopfront, checking Google Maps on a phone" ratio="4-5" />
          </div>
        </div>
      </section>

      <Section
        id="problem"
        title="Your customers are searching nearby. Are they finding you — or the business down the road?"
        intro={
          <p>
            When someone nearby needs what you sell, they search on their phone and choose from the handful of businesses Google
            shows them. Most never scroll past the map.
          </p>
        }
      >
        <ul className="feature-grid">
          <li className="feature">
            <h3>The Map Pack decides a lot</h3>
            <p>
              The map listings at the top of local searches get much of the attention. If your Google Business Profile is incomplete
              or out of date, a competitor takes that spot.
            </p>
          </li>
          <li className="feature">
            <h3>Reviews tip the balance</h3>
            <p>
              Customers compare star ratings, how many reviews you have and how recent they are — and whether you reply. A few old
              reviews rarely win against a steady stream of new ones.
            </p>
          </li>
          <li className="feature">
            <h3>You are busy running the business</h3>
            <p>
              Posting, asking for reviews, fixing listings and updating your website takes time most owners do not have. So it
              slips — and visibility slips with it.
            </p>
          </li>
        </ul>
      </Section>

      <Section id="how" title="Found. Trusted. Chosen." tone="muted" intro={<p>How we help local customers pick you, in three steps.</p>}>
        <ol className="steps-grid">
          <li className="step-card">
            <span className="step-number" aria-hidden="true">
              1
            </span>
            <h3>Found</h3>
            <p>
              We set up and maintain your Google Business Profile, listings and website so you show up clearly for the searches and
              suburbs that matter to you.
            </p>
          </li>
          <li className="step-card">
            <span className="step-number" aria-hidden="true">
              2
            </span>
            <h3>Trusted</h3>
            <p>
              We help you gather genuine reviews, keep your details consistent everywhere and stay active, so customers can see you
              are real, local and reliable.
            </p>
          </li>
          <li className="step-card">
            <span className="step-number" aria-hidden="true">
              3
            </span>
            <h3>Chosen</h3>
            <p>
              We make it easy to call, book or visit, then track which enquiries come from where — and report it all in plain
              English.
            </p>
          </li>
        </ol>
      </Section>

      <Section
        id="packages"
        title="Choose how much of your area you want to own."
        intro={<p>Clear monthly packages. All prices + GST, ad spend separate. No ranking promises — just the work that gives you the best chance.</p>}
      >
        <div className="package-grid">
          {packages.map((p) => (
            <PackageCard key={p.slug} pkg={p} featured={p.slug === 'silver'} />
          ))}
        </div>
        <p className="custom-note">
          <strong>{customPackage.name}:</strong> {customPackage.summary} <a href="/packages#custom">Learn about custom plans</a>.
        </p>
      </Section>

      <Section id="services" title="Everything your business needs to win locally." tone="muted">
        <CardGrid cta="home_service_card" items={services.map((s) => ({ href: `/services/${s.slug}`, title: s.name, body: s.cardSummary }))} />
      </Section>

      <Section
        id="locations"
        title="Local to Melbourne. Available Australia-wide."
        intro={
          <p>
            We are based in Melbourne. We meet in person or by video across Greater Melbourne, by video (and in person by arrangement)
            in Geelong and regional Victoria, and fully remotely everywhere else in Australia.
          </p>
        }
      >
        <CardGrid
          cta="home_location_card"
          items={locations.map((l) => ({ href: l.path, title: l.name, body: l.cardSummary }))}
        />
      </Section>

      <Section id="industries" title="Local marketing built around your industry." tone="muted">
        <CardGrid cta="home_industry_card" items={industries.map((i) => ({ href: `/industries/${i.slug}`, title: i.name, body: i.cardSummary }))} />
      </Section>

      {caseStudies.length ? (
        <Section id="proof" title="Results from local businesses like yours">
          <CaseStudyList items={caseStudies} />
        </Section>
      ) : null}

      <section className="section lead-magnet" aria-labelledby="lead-heading">
        <div className="container lead-inner">
          <div>
            <h2 id="lead-heading" className="section-title">
              How visible is your business in your area?
            </h2>
            <p>
              Get a free local visibility check-up. We look at your Google Business Profile, Map Pack presence, reviews, business
              details, website local signals, local content, social and AI-search readiness — and tell you honestly what we find.
            </p>
            <p className="form-note">Some checks are done automatically; the rest are reviewed by a person on our team within 1 business day.</p>
          </div>
          <a className="btn btn-primary btn-lg" href={CHECKUP_PATH} data-cta="checkup_lead_magnet">
            {CHECKUP_CTA}
          </a>
        </div>
      </section>

      <ClosingCta location="home" />
    </>
  );
}
