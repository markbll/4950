import { getPackage, formatPrice } from '../data/packages';
import { channelOf, getService, services, SERVICE_GROUPS } from '../data/services';
import { getIndustry } from '../data/industries';
import type { RouteDef } from '../routes';
import { CardGrid, Checklist, CheckupButton, ClosingCta, FaqList, PageHero, Section, SecondaryButton } from '../components/Blocks';

export function ServicesIndex({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Services" title="Everything your business needs to win locally">
        <p>
          Complete marketing and communication solutions, online and offline, built around one goal: helping people nearby find
          you, trust you and choose you. Many are included in our <a href="/packages">monthly packages</a>; the rest are quoted
          to suit your business.
        </p>
      </PageHero>
      {SERVICE_GROUPS.map((g, i) => (
        <Section key={g.channel} id={`services-${g.channel}`} title={g.title} tone={i % 2 ? 'muted' : 'default'} intro={<p>{g.intro}</p>}>
          <CardGrid
            cta="services_card"
            items={services.filter((s) => channelOf(s) === g.channel).map((s) => ({ href: `/services/${s.slug}`, title: s.name, body: s.cardSummary }))}
          />
        </Section>
      ))}
      <ClosingCta location="services" />
    </>
  );
}

const pkgLabel = (p: string[] | 'custom') =>
  p === 'custom' ? 'Big Cat Growth (custom)' : p.map((s) => getPackage(s)?.name ?? s).join(', ');

export function ServiceDetail({ route }: { route: RouteDef }) {
  const s = getService(route.slug!)!;
  const pkg = getPackage(s.relatedPackage)!;
  // Offline services (and any service only available as a custom quote) are not bundled into a monthly package.
  const quoted = channelOf(s) === 'offline' || s.inclusions.every((i) => i.packages === 'custom');
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
            {quoted ? `Pairs well with ${pkg.name}: ${pkg.theme}` : `Start with ${pkg.name}: ${pkg.theme}`}
          </h2>
          {quoted ? (
            <p>
              {s.name} is quoted to suit your business and budget. Production, printing, media and event costs are always
              agreed up front and billed separately, like ad spend. It works best alongside our {pkg.name} package from{' '}
              {formatPrice(pkg.priceMonthly)}/month + GST, so your offline and online marketing point to the same place.
            </p>
          ) : (
            <p>
              {s.name} is part of our {pkg.name} package from {formatPrice(pkg.priceMonthly)}/month + GST. {pkg.bestFor}
            </p>
          )}
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
