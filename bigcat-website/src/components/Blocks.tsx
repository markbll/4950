import type { ReactNode } from 'react';
import type { Crumb } from '../routes';
import type { Faq } from '../data/services';
import { formatPrice, type Package } from '../data/packages';
import { CHECKUP_CTA, CHECKUP_PATH } from '../constants';
import { showTodoMarkers } from '../config';

export function Breadcrumbs({ items }: { items: Crumb[] }) {
  if (items.length < 2) return null;
  return (
    <nav className="breadcrumbs" aria-label="Breadcrumb">
      <ol>
        {items.map((c, i) => (
          <li key={c.path}>
            {i === items.length - 1 ? <span aria-current="page">{c.name}</span> : <a href={c.path}>{c.name}</a>}
          </li>
        ))}
      </ol>
    </nav>
  );
}

export function PageHero({
  eyebrow,
  title,
  children,
  crumbs,
  actions,
}: {
  eyebrow?: string;
  title: string;
  children?: ReactNode;
  crumbs?: Crumb[];
  actions?: ReactNode;
}) {
  return (
    <section className="page-hero">
      <div className="container">
        {crumbs ? <Breadcrumbs items={crumbs} /> : null}
        {eyebrow ? <p className="eyebrow">{eyebrow}</p> : null}
        <h1>{title}</h1>
        {children ? <div className="page-hero-body">{children}</div> : null}
        {actions ? <div className="actions">{actions}</div> : null}
      </div>
    </section>
  );
}

export function Section({
  id,
  title,
  intro,
  tone = 'default',
  children,
  headingLevel = 2,
}: {
  id: string;
  title: string;
  intro?: ReactNode;
  tone?: 'default' | 'muted' | 'dark';
  children?: ReactNode;
  headingLevel?: 2 | 3;
}) {
  const H = headingLevel === 2 ? 'h2' : 'h3';
  return (
    <section className={`section section-${tone}`} aria-labelledby={`${id}-heading`}>
      <div className="container">
        <H id={`${id}-heading`} className="section-title">
          {title}
        </H>
        {intro ? <div className="section-intro">{intro}</div> : null}
        {children}
      </div>
    </section>
  );
}

export function CheckupButton({ location, label = CHECKUP_CTA }: { location: string; label?: string }) {
  return (
    <a className="btn btn-primary" href={CHECKUP_PATH} data-cta={`checkup_${location}`}>
      {label}
    </a>
  );
}

export function SecondaryButton({ href, children, cta }: { href: string; children: ReactNode; cta: string }) {
  return (
    <a className="btn btn-secondary" href={href} data-cta={cta}>
      {children}
    </a>
  );
}

export function Checklist({ items, className = '' }: { items: string[]; className?: string }) {
  return (
    <ul className={`checklist ${className}`}>
      {items.map((i) => (
        <li key={i}>{i}</li>
      ))}
    </ul>
  );
}

export interface CardItem {
  href: string;
  title: string;
  body: string;
  meta?: string;
}

export function CardGrid({ items, cta }: { items: CardItem[]; cta: string }) {
  return (
    <ul className="card-grid">
      {items.map((c) => (
        <li key={c.href} className="card card-link">
          <h3 className="card-title">
            <a href={c.href} data-cta={cta}>
              {c.title}
            </a>
          </h3>
          <p>{c.body}</p>
          {c.meta ? <p className="card-meta">{c.meta}</p> : null}
        </li>
      ))}
    </ul>
  );
}

export function FaqList({ faqs, id = 'faqs', title = 'Frequently asked questions' }: { faqs: Faq[]; id?: string; title?: string }) {
  if (!faqs.length) return null;
  return (
    <Section id={id} title={title} tone="muted">
      <div className="faq-list">
        {faqs.map((f) => (
          <details key={f.q} className="faq">
            <summary>{f.q}</summary>
            <p>{f.a}</p>
          </details>
        ))}
      </div>
    </Section>
  );
}

export function ClosingCta({
  title = 'Ready to be the business locals find first?',
  body = 'Tell us about your business and the area you want to own. We will show you where you stand and what to do next.',
  location,
}: {
  title?: string;
  body?: string;
  location: string;
}) {
  return (
    <section className="section section-dark closing-cta" aria-labelledby={`closing-${location}-heading`}>
      <div className="container closing-inner">
        <h2 id={`closing-${location}-heading`} className="section-title">
          {title}
        </h2>
        <p>{body}</p>
        <div className="actions">
          <a className="btn btn-primary" href="/contact" data-cta={`talk_${location}`}>
            Talk to Big Cat Marketing
          </a>
          <a className="btn btn-ghost" href={CHECKUP_PATH} data-cta={`checkup_closing_${location}`}>
            {CHECKUP_CTA}
          </a>
        </div>
      </div>
    </section>
  );
}

export function PackageCard({ pkg, featured = false, headingLevel = 3 }: { pkg: Package; featured?: boolean; headingLevel?: 2 | 3 }) {
  const H = headingLevel === 2 ? 'h2' : 'h3';
  const top = pkg.inclusions.slice(0, 5);
  return (
    <article className={`card package-card${featured ? ' package-featured' : ''}`}>
      <H className="package-name">
        {pkg.name} <span className="package-theme">{pkg.theme}</span>
      </H>
      <p className="price">
        <span className="price-amount">{formatPrice(pkg.priceMonthly)}</span>
        <span className="price-unit">/month + GST</span>
      </p>
      <p>{pkg.summary}</p>
      {pkg.includesPrevious ? (
        <p className="package-includes">Everything in {pkg.includesPrevious[0]!.toUpperCase() + pkg.includesPrevious.slice(1)}, plus:</p>
      ) : null}
      <Checklist items={top} />
      <a className="btn btn-secondary btn-block" href={`/packages/${pkg.slug}`} data-cta={`package_${pkg.slug}`}>
        See {pkg.name} in full
      </a>
    </article>
  );
}

/**
 * Clearly-marked image placeholder with a fixed aspect ratio (no layout shift).
 * TODO(asset): replace each with an authentic, licensed photo of a
 * Melbourne / Victorian small business, compressed to AVIF/WebP with
 * width/height set and loading="lazy" below the fold.
 */
export function ImagePlaceholder({ label, ratio = '4-3' }: { label: string; ratio?: '4-3' | '4-5' | '3-2' }) {
  // Ratio via class (not an inline style) so the CSP can forbid inline styles.
  return (
    <figure className={`img-placeholder ratio-${ratio}`}>
      <figcaption>
        <span className="img-placeholder-tag">Image placeholder</span>
        {label}
      </figcaption>
    </figure>
  );
}

export function DraftNotice({ fields }: { fields: string[] }) {
  if (!showTodoMarkers || !fields.length) return null;
  return (
    <p className="draft-notice" data-draft-fields={fields.join(',')}>
      Draft content — needs local review before launch ({fields.join(', ')}).
    </p>
  );
}
