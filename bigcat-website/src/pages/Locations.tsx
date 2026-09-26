import { business } from '../data/business';
import { getLocation, locations, melbourneRegions, type Location } from '../data/locations';
import { getService } from '../data/services';
import { getIndustry } from '../data/industries';
import { caseStudiesFor } from '../data/caseStudies';
import type { RouteDef } from '../routes';
import { CardGrid, Checklist, CheckupButton, ClosingCta, DraftNotice, FaqList, PageHero, Section } from '../components/Blocks';
import { MapEmbed } from '../components/MapEmbed';
import { CaseStudyList } from './shared';

const MEETING_TEXT: Record<Location['meeting'], string> = {
  in_person_or_video: 'We can meet you in person or by video — whichever suits.',
  video_in_person_by_arrangement: 'We work by video, and can meet in person by arrangement.',
  remote: 'We work fully remotely, by video and online.',
};

function ConsultationOptions({ loc }: { loc: Location }) {
  return (
    <div className="consult-options">
      <p>{MEETING_TEXT[loc.meeting]}</p>
      <div className="actions">
        {loc.meeting !== 'remote' ? (
          <a className="btn btn-secondary" href="/contact?meeting=in_person" data-consultation="in_person" data-cta-location={loc.slug}>
            {loc.meeting === 'in_person_or_video' ? 'Book an in-person chat' : 'Ask about meeting in person'}
          </a>
        ) : null}
        <a className="btn btn-secondary" href="/contact?meeting=video" data-consultation="video" data-cta-location={loc.slug}>
          Book a video call
        </a>
        <CheckupButton location={`location_${loc.slug}`} />
      </div>
    </div>
  );
}

export function LocationsIndex({ route }: { route: RouteDef }) {
  const regions = melbourneRegions();
  const melb = getLocation('melbourne')!;
  const regional = getLocation('regional-victoria')!;
  const aus = getLocation('australia')!;
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow="Areas we serve" title="Local to Melbourne. Available Australia-wide.">
        <p>{business.serviceAreaLine}.</p>
      </PageHero>
      <Section id="tiers" title="How we work in each area">
        <ul className="tier-grid">
          {business.serviceAreas.map((t) => {
            const l = getLocation(t.locationSlug)!;
            return (
              <li key={t.tier} className="card">
                <h3 className="card-title">
                  <a href={l.path}>{t.label}</a>
                </h3>
                <p>{t.delivery}.</p>
              </li>
            );
          })}
        </ul>
      </Section>
      <Section id="melbourne-regions" title="Greater Melbourne" tone="muted" intro={<p>{melb.cardSummary}</p>}>
        <CardGrid
          cta="locations_card"
          items={[{ href: melb.path, title: 'Greater Melbourne overview', body: 'How we approach local marketing across Melbourne.' }, ...regions.map((r) => ({ href: r.path, title: r.name, body: r.cardSummary }))]}
        />
      </Section>
      <Section id="beyond" title="Beyond Melbourne">
        <CardGrid
          cta="locations_card"
          items={[regional, aus].map((l) => ({ href: l.path, title: l.name, body: l.cardSummary }))}
        />
        <p className="form-note">
          We do not create separate pages for individual suburbs. Each region page covers the suburbs and towns within it.
        </p>
      </Section>
      <ClosingCta location="locations" />
    </>
  );
}

export function LocationDetail({ route }: { route: RouteDef }) {
  const loc = getLocation(route.slug!)!;
  const isHub = loc.slug === 'melbourne';
  const cases = caseStudiesFor({ region: loc.slug });
  const siblings = loc.parent === 'melbourne' ? melbourneRegions().filter((r) => r.slug !== loc.slug) : [];
  return (
    <>
      <PageHero crumbs={route.breadcrumbs} eyebrow={loc.tier === 'melbourne' ? 'Greater Melbourne' : loc.tier === 'regional_vic' ? 'Regional Victoria' : 'Australia-wide'} title={loc.h1}>
        {loc.intro.map((p) => (
          <p key={p}>{p}</p>
        ))}
        <DraftNotice fields={loc.needsReview} />
      </PageHero>

      {isHub ? (
        <Section id="regions" title="Melbourne regions we cover" tone="muted">
          <CardGrid cta="melbourne_region_card" items={melbourneRegions().map((r) => ({ href: r.path, title: r.name, body: r.cardSummary }))} />
        </Section>
      ) : null}

      {loc.suburbs.length ? (
        <Section id="suburbs" title={loc.tier === 'regional_vic' ? 'Towns and areas we work with' : 'Suburbs in this region'} tone={isHub ? 'default' : 'muted'}>
          <ul className="suburb-list">
            {loc.suburbs.map((s) => (
              <li key={s}>{s}</li>
            ))}
          </ul>
          <p className="form-note">Not listed? If you are nearby, we can still help — get in touch.</p>
        </Section>
      ) : null}

      <Section id="landscape" title="The local business landscape">
        {loc.landscape.map((p) => (
          <p key={p}>{p}</p>
        ))}
      </Section>

      <Section id="challenges" title="Local search challenges here" tone="muted">
        <Checklist items={loc.searchChallenges} />
      </Section>

      <Section id="services" title="Services that help most">
        <ul className="card-grid">
          {loc.relevantServices.map((slug) => {
            const s = getService(slug);
            return s ? (
              <li key={slug} className="card">
                <h3 className="card-title">
                  <a href={`/services/${slug}`}>{s.name}</a>
                </h3>
                <p>{s.cardSummary}</p>
              </li>
            ) : null;
          })}
        </ul>
        <p>
          See our <a href="/packages">packages</a> — prices + GST, ad spend separate.
        </p>
      </Section>

      <Section id="industries" title="Common industries we help here" tone="muted">
        <ul className="link-list link-list-inline">
          {loc.commonIndustries.map((slug) => {
            const i = getIndustry(slug);
            return i ? (
              <li key={slug}>
                <a href={`/industries/${slug}`}>{i.name}</a>
              </li>
            ) : null;
          })}
        </ul>
      </Section>

      {cases.length ? (
        <Section id="cases" title="Results in this area">
          <CaseStudyList items={cases} />
        </Section>
      ) : null}

      <Section id="meet" title="Working together">
        <ConsultationOptions loc={loc} />
      </Section>

      {isHub ? (
        <Section id="map" title="Melbourne-based" tone="muted">
          <MapEmbed title="Map of Melbourne, Victoria" />
        </Section>
      ) : null}

      <FaqList faqs={loc.faqs} />

      {siblings.length ? (
        <Section id="nearby" title="Other Melbourne regions">
          <ul className="link-list link-list-inline">
            <li>
              <a href="/locations/melbourne">Greater Melbourne</a>
            </li>
            {siblings.map((r) => (
              <li key={r.slug}>
                <a href={r.path}>{r.name}</a>
              </li>
            ))}
          </ul>
        </Section>
      ) : null}

      {!isHub && loc.parent !== 'melbourne' ? (
        <Section id="other-areas" title="Other areas we serve">
          <ul className="link-list link-list-inline">
            {locations
              .filter((l) => l.slug !== loc.slug && l.parent === null)
              .map((l) => (
                <li key={l.slug}>
                  <a href={l.path}>{l.name}</a>
                </li>
              ))}
          </ul>
        </Section>
      ) : null}

      <ClosingCta location={`location_${loc.slug}`} />
    </>
  );
}
