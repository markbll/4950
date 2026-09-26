import { customPackage, formatPrice, getPackage, GST_NOTE, packages } from '../data/packages';
import { getService } from '../data/services';
import type { RouteDef } from '../routes';
import { Checklist, CheckupButton, ClosingCta, FaqList, PackageCard, PageHero, Section } from '../components/Blocks';

const comparisonRows: { label: string; values: [string, string, string] }[] = [
  { label: 'Google Business Profile optimisation', values: ['Yes', 'Yes', 'Up to 3 locations'] },
  { label: 'Google Business Profile posts', values: ['4 / month', '4 / month', '4 / month'] },
  { label: 'Service areas in keyword map', values: ['1', 'Up to 3', 'Up to 3 + expanded'] },
  { label: 'Local content', values: ['1 / month', '2 / month', '4 / month'] },
  { label: 'Social posts', values: ['2 / month', '8 / month', '12 / month'] },
  { label: 'Email or SMS campaigns', values: ['—', '1 / month', '2 / month'] },
  { label: 'Competitor research & rank tracking', values: ['—', 'Yes', 'Yes'] },
  { label: 'Conversion tracking', values: ['—', 'Yes', 'Yes'] },
  { label: 'Google Ads', values: ['—', 'Set-up (management optional)', 'Managed (incl. LSA where eligible)'] },
  { label: 'Meta Ads management', values: ['—', '—', 'Yes'] },
  { label: 'Review program & reputation monitoring', values: ['Set-up + response drafting', 'Set-up + response drafting', 'Full program'] },
  { label: 'Minor website updates', values: ['—', '—', 'Up to 2 hrs / month'] },
  { label: 'Reporting', values: ['Monthly summary', 'Monthly meeting + report', 'Full monthly dashboard'] },
  { label: 'Reviews with you', values: ['Quarterly', 'Monthly + quarterly planning', 'Monthly + priority support'] },
];

export function PackagesIndex({ route }: { route: RouteDef }) {
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Packages" title="Choose how much of your area you want to own">
        <p>Three clear monthly packages, plus custom plans for bigger businesses. {GST_NOTE}</p>
      </PageHero>
      <Section id="package-cards" title="Our packages">
        <div className="package-grid">
          {packages.map((p) => (
            <PackageCard key={p.slug} pkg={p} featured={p.slug === 'silver'} />
          ))}
        </div>
      </Section>
      <Section id="compare" title="Compare packages" tone="muted">
        <div className="table-wrap" role="region" aria-labelledby="compare-heading" tabIndex={0}>
          <table className="compare-table">
            <caption className="visually-hidden">Package comparison. Prices ex GST, ad spend separate.</caption>
            <thead>
              <tr>
                <th scope="col">Inclusion</th>
                {packages.map((p) => (
                  <th scope="col" key={p.slug}>
                    <a href={`/packages/${p.slug}`}>{p.name}</a>
                    <span className="th-price">{formatPrice(p.priceMonthly)}/mo + GST</span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {comparisonRows.map((r) => (
                <tr key={r.label}>
                  <th scope="row">{r.label}</th>
                  {r.values.map((v, i) => (
                    <td key={i}>{v}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>
      <section className="section" id="custom" aria-labelledby="custom-heading">
        <div className="container custom-package">
          <h2 id="custom-heading" className="section-title">
            {customPackage.name} — custom plans
          </h2>
          <p>{customPackage.summary}</p>
          <Checklist items={customPackage.examples} />
          <a className="btn btn-primary" href="/contact" data-cta="custom_package_contact">
            Talk to us about a custom plan
          </a>
        </div>
      </section>
      <Section id="promise" title="What we will — and won't — promise" tone="muted">
        <p>
          We will do the work, show you what we did and report honestly on what changed. We will not promise rankings, Map Pack
          positions or a number of leads, because nobody can control those. Anyone who guarantees them is guessing.
        </p>
      </Section>
      <ClosingCta location="packages" />
    </>
  );
}

export function PackageDetail({ route }: { route: RouteDef }) {
  const p = getPackage(route.slug!)!;
  const prev = p.includesPrevious ? getPackage(p.includesPrevious) : undefined;
  const others = packages.filter((o) => o.slug !== p.slug);
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow={`${p.name} package`} title={`${p.name}: ${p.theme}`}>
        <p className="price price-hero">
          <span className="price-amount">{formatPrice(p.priceMonthly)}</span>
          <span className="price-unit">/month + GST</span>
        </p>
        <p>{p.summary}</p>
        <p className="form-note">{GST_NOTE}</p>
      </PageHero>
      <Section id="best-for" title="Who it suits">
        <p>{p.bestFor}</p>
      </Section>
      <Section id="inclusions" title="What's included" tone="muted">
        {prev ? (
          <p>
            Everything in <a href={`/packages/${prev.slug}`}>{prev.name}</a>, plus:
          </p>
        ) : null}
        <Checklist items={p.inclusions} className="checklist-columns" />
      </Section>
      <Section id="related-services" title="Services in this package">
        <ul className="link-list">
          {p.relatedServices.map((slug) => {
            const s = getService(slug);
            return s ? (
              <li key={slug}>
                <a href={`/services/${slug}`}>{s.name}</a> — {s.cardSummary}
              </li>
            ) : null;
          })}
        </ul>
      </Section>
      <FaqList faqs={p.faqs} />
      <Section id="other-packages" title="Compare other packages">
        <div className="package-grid package-grid-2">
          {others.map((o) => (
            <PackageCard key={o.slug} pkg={o} />
          ))}
        </div>
        <p className="actions">
          <CheckupButton location={`package_${p.slug}`} />
        </p>
      </Section>
      <ClosingCta location={`package_${p.slug}`} />
    </>
  );
}
