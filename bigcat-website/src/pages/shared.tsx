import type { CaseStudy } from '../data/caseStudies';
import { getIndustry } from '../data/industries';
import { getLocation } from '../data/locations';

export function CaseStudyList({ items }: { items: CaseStudy[] }) {
  if (!items.length) return null;
  return (
    <ul className="card-grid">
      {items.map((c) => {
        const loc = getLocation(c.region);
        const ind = getIndustry(c.industry);
        return (
          <li key={c.slug} className="card case-card" id={c.slug}>
            <p className="tags">
              {loc ? <a href={loc.path}>{loc.shortName}</a> : null}
              {ind ? <a href={`/industries/${ind.slug}`}>{ind.name}</a> : null}
              {c.package !== 'custom' ? <a href={`/packages/${c.package}`}>{c.package}</a> : null}
            </p>
            <h3>{c.client}</h3>
            <p>{c.summary}</p>
            <ul className="checklist">
              {c.outcomes.map((o) => (
                <li key={o.text}>
                  {o.text} <span className="card-meta">({o.source}, {o.period})</span>
                </li>
              ))}
            </ul>
          </li>
        );
      })}
    </ul>
  );
}
