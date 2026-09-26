import { getPackage, formatPrice } from '../data/packages';
import { getService, services } from '../data/services';
import { getIndustry } from '../data/industries';
import type { RouteDef } from '../routes';
import { CardGrid, Checklist, CheckupButton, ClosingCta, FaqList, PageHero, Section, SecondaryButton } from '../components/Blocks';

export function ServicesIndex({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Services" title="Everything your business needs to win locally">
        <p>
          Every service is built around one goal: helping people nearby find you, trust you and choose you. Most are included in our{' '}
          <a href="/packages">monthly packages</a>.
        </p>
      </PageHero>
      <Section id="all-services" title="Our local marketing services">
        <CardGrid cta="services_card" items={services.map((s) => ({ href: `/services/${s.slug}`, title: s.name, body: s.cardSummary }))} />
      </Section>
      <ClosingCta location="services" />
    </>
  );
}

const pkgLabel = (p: string[] | 'custom') =>
  p === 'custom' ? 'Big Cat Growth (custom)' : p.map((s) => getPackage(s)?.name ?? s).join(', ');

export function ServiceDetail({ route }: { route: RouteDef }) {
  const s = getService(route.slug!)!;
  const pkg = getPackage(s.relatedPackage)!;
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow={s.name} title={s.heroTitle}>
        <p>{s.heroBody}</p>
      </PageHero>
      <Section id="problem" title={`Why ${s.name.toLowerCase()} matters for local business`}>
        {s.problem.map((p) => (
          <p key={p}>{p}</p>
        ))}
      </Section>
      <Section id="deliverables" title="What we deliver" tone="muted">
        <Checklist items={s.deliverables} className="checklist-columns" />
      </Section>
      <Section id="inclusions" title="Included in our packages">
        <div className="table-wrap" role="region" aria-labelledby="inclusions-heading" tabIndex={0}>
          <table className="simple-table">
            <thead>
              <tr>
                <th scope="col">Inclusion</th>
                <th scope="col">Package</th>
              </tr>
            </thead>
            <tbody>
              {s.inclusions.map((i) => (
                <tr key={i.item}>
                  <th scope="row">{i.item}</th>
                  <td>{pkgLabel(i.packages)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>
      <Section id="process" title="How it works" tone="muted">
        <ol className="steps-grid">
          {s.process.map((p, i) => (
            <li key={p.title} className="step-card">
              <span className="step-number" aria-hidden="true">
                {i + 1}
              </span>
              <h3>{p.title}</h3>
              <p>{p.body}</p>
            </li>
          ))}
        </ol>
      </Section>
      <Section id="suits" title="Who it suits">
        <Checklist items={s.suits} />
        <p>
          Common industries:{' '}
          {s.relatedIndustries
            .map((slug) => getIndustry(slug))
            .filter(Boolean)
            .map((ind, idx, arr) => (
              <span key={ind!.slug}>
                <a href={`/industries/${ind!.slug}`}>{ind!.name}</a>
                {idx < arr.length - 1 ? ', ' : '.'}
              </span>
            ))}
        </p>
      </Section>
      <FaqList faqs={s.faqs} />
      <section className="section" aria-labelledby="related-package-heading">
        <div className="container related-package">
          <h2 id="related-package-heading" className="section-title">
            Start with {pkg.name}: {pkg.theme}
          </h2>
          <p>
            {s.name} is part of our {pkg.name} package from {formatPrice(pkg.priceMonthly)}/month + GST. {pkg.bestFor}
          </p>
          <div className="actions">
            <SecondaryButton href={`/packages/${pkg.slug}`} cta={`service_${s.slug}_package`}>
              See the {pkg.name} package
            </SecondaryButton>
            <CheckupButton location={`service_${s.slug}`} />
          </div>
        </div>
      </section>
      <ClosingCta location={`service_${s.slug}`} />
    </>
  );
}
