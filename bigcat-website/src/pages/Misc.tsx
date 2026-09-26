import { business } from '../data/business';
import { caseStudies } from '../data/caseStudies';
import { industries } from '../data/industries';
import { locations } from '../data/locations';
import { services } from '../data/services';
import type { RouteDef } from '../routes';
import { CHECKUP_CTA, CHECKUP_PATH } from '../constants';
import { Checklist, CheckupButton, ClosingCta, ImagePlaceholder, PageHero, Section } from '../components/Blocks';
import { EmailLink, NapBlock, PhoneLink } from '../components/Nap';
import { Island } from '../components/Island';
import { MapEmbed } from '../components/MapEmbed';
import { Todo } from '../components/Todo';
import CheckupForm from '../islands/CheckupForm';
import ContactForm from '../islands/ContactForm';
import { CaseStudyList } from './shared';

export function Checkup({ route }: { route: RouteDef }) {
  const checkupProps = {
    industryOptions: industries.map((i) => ({ value: i.slug, label: i.name })),
    serviceOptions: services.map((s) => s.name),
  };
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Free Local Visibility Check-up" title="How visible is your business in your area?">
        <p>
          Answer a few quick questions. We will check what we can straight away and have a person on our team review the rest
          within 1 business day. No invented scores — just what we actually find.
        </p>
      </PageHero>
      <section className="section" aria-label="Check-up form">
        <div className="container checkup-layout">
          <div className="checkup-main">
            <Island name="checkup" props={checkupProps}>
              <CheckupForm {...checkupProps} />
            </Island>
            <noscript>
              <p className="notice">
                The check-up form needs JavaScript. You can also <a href="/contact">contact us</a> directly
                {business.email ? (
                  <>
                    {' '}
                    at <a href={`mailto:${business.email}`}>{business.email}</a>
                  </>
                ) : null}
                .
              </p>
            </noscript>
          </div>
          <aside className="checkup-aside" aria-labelledby="checkup-covers">
            <h2 id="checkup-covers" className="aside-title">
              What we look at
            </h2>
            <Checklist
              items={[
                'Google Business Profile',
                'Map Pack presence',
                'Reviews',
                'NAP consistency (name, address, phone)',
                'Website local signals',
                'Local content',
                'Social',
                'AI-search readiness',
              ]}
            />
            <p className="form-note">
              Website signals (titles, headings, phone number, structured data, mobile set-up) are checked automatically from your
              public home page. Profile, Map Pack, reviews and citations are reviewed by our team.
            </p>
          </aside>
        </div>
      </section>
    </>
  );
}

export function Results({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Results" title="Results and case studies">
        <p>We only publish results our clients have approved, with the source and time period for every figure.</p>
      </PageHero>
      {caseStudies.length ? (
        <Section id="cases" title="Case studies">
          <CaseStudyList items={caseStudies} />
        </Section>
      ) : (
        <Section id="cases" title="Case studies are on their way">
          <p>
            We are preparing case studies with our clients&apos; permission. Rather than show sample or made-up results, this page
            stays honest until they are ready.
          </p>
          <p>In the meantime, the best way to see what we could do for you is a free check-up of your own business.</p>
          <p className="actions">
            <CheckupButton location="results_empty" />
          </p>
        </Section>
      )}
      <Section id="how-we-report" title="How we report results" tone="muted">
        <Checklist
          items={[
            'Every figure comes from a named source, such as Google Business Profile insights, Search Console or your call tracking.',
            'We state the time period and compare like with like.',
            'We never promise rankings, Map Pack positions or lead numbers.',
            'Case studies are tagged by region and industry so you can find businesses like yours.',
          ]}
        />
        <p>
          Browse by <a href="/industries">industry</a> or <a href="/locations">area</a>.
        </p>
      </Section>
      <ClosingCta location="results" />
    </>
  );
}

export function About({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="About" title={`About ${business.name}`}>
        <p>{business.description}</p>
      </PageHero>
      <Section id="story" title="Who we are">
        <div className="two-col">
          <div>
            <p>
              {/* TODO(content): founder / team story, in the owner's own words. Do not invent history, awards or client numbers. */}
              <Todo label="founder and team story — supplied and approved by Big Cat Marketing" />
            </p>
            <p>
              We are a Melbourne-based team focused on one thing: helping small and medium-sized businesses get found by the
              customers near them.
            </p>
          </div>
          <ImagePlaceholder label="Big Cat Marketing team photo (Melbourne)" ratio="3-2" />
        </div>
      </Section>
      <Section id="principles" title="How we work" tone="muted">
        <ul className="feature-grid">
          <li className="feature">
            <h3>Plain English</h3>
            <p>No jargon. You will always know what we are doing and why.</p>
          </li>
          <li className="feature">
            <h3>You own everything</h3>
            <p>Your Google Business Profile, ad accounts, website and content stay in your name.</p>
          </li>
          <li className="feature">
            <h3>Honest reporting</h3>
            <p>We report what changed and where it came from. We never promise rankings, Map Pack spots or lead numbers.</p>
          </li>
          <li className="feature">
            <h3>Local first</h3>
            <p>Every plan starts with where your customers are and how they search.</p>
          </li>
        </ul>
      </Section>
      <Section id="where" title="Where we work">
        <ul className="link-list">
          {business.serviceAreas.map((t) => (
            <li key={t.tier}>
              <a href={`/locations/${t.locationSlug}`}>{t.label}</a> — {t.delivery.toLowerCase()}
            </li>
          ))}
        </ul>
      </Section>
      <ClosingCta location="about" />
    </>
  );
}

export function Contact({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Contact" title="Talk to Big Cat Marketing">
        <p>Tell us about your business and the area you want to own. We will get back to you to arrange a time to talk.</p>
      </PageHero>
      <section className="section" aria-label="Contact options">
        <div className="container contact-layout">
          <div className="contact-main">
            <h2 className="section-title">Send us a message</h2>
            <Island name="contact" props={{}}>
              <ContactForm />
            </Island>
            <noscript>
              <p className="notice">The contact form needs JavaScript. Please use the phone or email details on this page.</p>
            </noscript>
          </div>
          <aside className="contact-aside" aria-labelledby="contact-details-heading">
            <h2 id="contact-details-heading" className="aside-title">
              Contact details
            </h2>
            <NapBlock location="contact" />
            <h3>Book a consultation</h3>
            <ul className="link-list">
              <li>
                <a href="/contact?meeting=in_person" data-consultation="in_person" data-cta-location="contact">
                  In person
                </a>{' '}
                — Greater Melbourne (regional Victoria by arrangement)
              </li>
              <li>
                <a href="/contact?meeting=video" data-consultation="video" data-cta-location="contact">
                  Video call
                </a>{' '}
                — anywhere in Australia
              </li>
            </ul>
            <p>
              Prefer to call? <PhoneLink location="contact_aside" />
              <br />
              Or email: <EmailLink location="contact_aside" />
            </p>
            <p>
              Not ready to talk? <a href={CHECKUP_PATH}>{CHECKUP_CTA}</a>.
            </p>
          </aside>
        </div>
      </section>
      <Section id="map" title="Melbourne-based, working Australia-wide" tone="muted">
        <MapEmbed title="Map of Melbourne, Victoria — Big Cat Marketing service area" />
      </Section>
    </>
  );
}

export function Privacy({ route }: { route: RouteDef }) {
  const email = business.email;
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} title="Privacy Policy">
        <p>
          {/* TODO(legal): have this policy reviewed by a qualified adviser before production. */}
          This policy explains how {business.legalName ?? business.name} handles personal information in line with the Australian
          Privacy Principles.
        </p>
        <p className="form-note">
          Last updated: <Todo label="date approved" />
        </p>
      </PageHero>
      <div className="section">
        <div className="container prose">
          <h2>What we collect</h2>
          <ul>
            <li>Details you give us in our forms: your name, business name, email, phone, suburb or town, state, website address and what you tell us about your business.</li>
            <li>If you request a check-up and give us a website address, we fetch that site&apos;s public home page once to check for local signals.</li>
            <li>Basic, anonymous website usage data (pages viewed, buttons clicked, campaign source) if analytics is enabled. We do not send your name, email or phone number to analytics.</li>
            <li>A one-way hashed version of your IP address, kept briefly to stop spam and abuse of our forms.</li>
          </ul>
          <h2>How we use it</h2>
          <ul>
            <li>To respond to your enquiry and prepare your check-up.</li>
            <li>To send you marketing emails, only if you have opted in.</li>
            <li>To protect our website from spam and misuse.</li>
          </ul>
          <h2>Who we share it with</h2>
          <p>
            We use service providers to run our website and email (for example, our web host and email provider). If enabled, Google
            Analytics measures anonymous site usage, and Google Maps provides map embeds. We do not sell your personal information.
            <Todo label="list actual providers (host, email/SMTP, email marketing platform)" />
          </p>
          <h2>How long we keep it</h2>
          <p>
            Form submissions are sent to our team by email; the website does not store them in a database. Anti-spam records are
            deleted automatically within 24 hours. We keep enquiry emails only as long as we need them to deal with you, then delete
            them. <Todo label="confirm internal email retention period" />
          </p>
          <h2>Marketing and the Spam Act</h2>
          <p>
            We only send marketing emails or SMS messages with your consent. Every message identifies us and includes a simple way
            to unsubscribe, and we act on unsubscribe requests promptly.
          </p>
          <h2>Access, correction and complaints</h2>
          <p>
            You can ask to see or correct the personal information we hold about you, or make a complaint, by contacting us
            {email ? (
              <>
                {' '}
                at <a href={`mailto:${email}`}>{email}</a>
              </>
            ) : (
              <>
                {' '}
                <Todo label="privacy contact email" />
              </>
            )}
            . If you are not satisfied with our response, you can contact the Office of the Australian Information Commissioner
            (OAIC) at <a href="https://www.oaic.gov.au/">oaic.gov.au</a>.
          </p>
        </div>
      </div>
    </>
  );
}

export function Terms({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} title="Website Terms of Use">
        <p>
          {/* TODO(legal): review by a qualified adviser before production. */}
          These terms apply to your use of this website. Engagements for our services are covered by a separate written proposal and
          agreement.
        </p>
      </PageHero>
      <div className="section">
        <div className="container prose">
          <h2>Information on this site</h2>
          <p>
            We aim to keep this website accurate and up to date, but it is general information only. It is not a guarantee of any
            particular result, ranking, Map Pack position or number of leads.
          </p>
          <h2>Prices</h2>
          <p>All prices are in Australian dollars and exclude GST. Advertising spend is separate and paid by the client. Prices may change; your written proposal confirms the price that applies to you.</p>
          <h2>Free check-up</h2>
          <p>
            The free local visibility check-up is an informal review based on publicly available information and the details you
            provide. Automated checks only cover what they say they cover; everything else is reviewed by a person.
          </p>
          <h2>Your rights under Australian Consumer Law</h2>
          <p>Nothing in these terms limits any rights you have under the Australian Consumer Law.</p>
          <h2>Business details</h2>
          <p>
            {business.legalName ?? business.name}
            {business.abn ? ` · ABN ${business.abn}` : null}
            <Todo label="legal entity name and ABN" />
          </p>
        </div>
      </div>
    </>
  );
}

export function NotFound() {
  return (
    <>
      <PageHero title="Sorry, we could not find that page">
        <p>The page may have moved when we updated our website. Try one of these instead:</p>
      </PageHero>
      <div className="section">
        <div className="container">
          <ul className="link-list">
            <li>
              <a href="/">Home</a>
            </li>
            <li>
              <a href="/packages">Packages</a>
            </li>
            <li>
              <a href="/services">Services</a>
            </li>
            <li>
              <a href="/locations">Areas we serve</a> — {locations.length} location pages
            </li>
            <li>
              <a href="/industries">Industries</a> — {industries.length} industries
            </li>
            <li>
              <a href={CHECKUP_PATH}>{CHECKUP_CTA}</a>
            </li>
            <li>
              <a href="/contact">Contact us</a>
            </li>
          </ul>
        </div>
      </div>
    </>
  );
}
