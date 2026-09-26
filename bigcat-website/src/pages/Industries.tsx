import { getIndustry, industries } from '../data/industries';
import { getService } from '../data/services';
import { getLocation } from '../data/locations';
import { getPackage, formatPrice } from '../data/packages';
import { caseStudiesFor } from '../data/caseStudies';
import type { RouteDef } from '../routes';
import { CardGrid, Checklist, CheckupButton, ClosingCta, DraftNotice, FaqList, PageHero, Section, SecondaryButton } from '../components/Blocks';
import { CaseStudyList } from './shared';

export function IndustriesIndex({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Industries" title="Local marketing built around your industry">
        <p>Customers search differently for a plumber, a physio and a café. We plan your local marketing around how your customers actually look for you.</p>
      </PageHero>
      <Section id="all-industries" title="Industries we work with">
        <CardGrid cta="industries_card" items={industries.map((i) => ({ href: `/industries/${i.slug}`, title: i.name, body: i.cardSummary }))} />
      </Section>
      <ClosingCta location="industries" />
    </>
  );
}

export function IndustryDetail({ route }: { route: RouteDef }) {
  const ind = getIndustry(route.slug!)!;
  const pkg = getPackage(ind.recommendedPackage)!;
  const cases = caseStudiesFor({ industry: ind.slug });
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow={ind.name} title={ind.heroTitle}>
        <p>{ind.heroBody}</p>
        <DraftNotice fields={ind.needsReview} />
      </PageHero>
      <Section id="intro" title={`How ${ind.name.toLowerCase()} customers find local businesses`}>
        {ind.intro.map((p) => (
          <p key={p}>{p}</p>
        ))}
        <p>
          <strong>Who we help:</strong> {ind.examples.join(', ')}.
        </p>
      </Section>
      <Section
        id="searches"
        title="Local searches your customers use"
        tone="muted"
        intro={<p>Illustrative examples of the kinds of local searches we plan for. We research the real terms for your area before we start.</p>}
      >
        <ul className="search-examples">
          {ind.searchExamples.map((q) => (
            <li key={q}>
              <span className="search-pill">{q}</span>
            </li>
          ))}
        </ul>
      </Section>
      <Section id="challenges" title="Common local challenges">
        <Checklist items={ind.challenges} />
      </Section>
      <Section id="service-mapping" title="How we help" tone="muted">
        <ul className="card-grid">
          {ind.serviceMapping.map((m) => {
            const s = getService(m.service);
            return s ? (
              <li key={m.service} className="card">
                <h3 className="card-title">
                  <a href={`/services/${s.slug}`}>{s.name}</a>
                </h3>
                <p>{m.why}</p>
              </li>
            ) : null;
          })}
        </ul>
      </Section>
      <Section id="where" title="Where we work with these businesses">
        <ul className="link-list">
          {ind.relatedLocations.map((slug) => {
            const l = getLocation(slug);
            return l ? (
              <li key={slug}>
                <a href={l.path}>{l.name}</a> — {l.cardSummary}
              </li>
            ) : null;
          })}
          <li>
            <a href="/locations">All areas we serve</a>
          </li>
        </ul>
      </Section>
      {cases.length ? (
        <Section id="cases" title="Results in this industry">
          <CaseStudyList items={cases} />
        </Section>
      ) : null}
      <FaqList faqs={ind.faqs} />
      <section className="section" aria-labelledby="industry-package-heading">
        <div className="container related-package">
          <h2 id="industry-package-heading" className="section-title">
            A good starting point: {pkg.name}
          </h2>
          <p>
            For {ind.name.toLowerCase()} businesses we usually suggest starting with {pkg.name} ({pkg.theme}) from {formatPrice(pkg.priceMonthly)}/month + GST. We will recommend what fits after your check-up.
          </p>
          <div className="actions">
            <SecondaryButton href={`/packages/${pkg.slug}`} cta={`industry_${ind.slug}_package`}>
              See {pkg.name}
            </SecondaryButton>
            <CheckupButton location={`industry_${ind.slug}`} />
          </div>
        </div>
      </section>
      <ClosingCta location={`industry_${ind.slug}`} />
    </>
  );
}
