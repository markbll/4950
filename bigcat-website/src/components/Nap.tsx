import { business } from '../data/business';
import { Todo } from './Todo';

export function PhoneLink({ className, location }: { className?: string; location: string }) {
  if (!business.phone) return <Todo label="business phone in src/data/business.ts" />;
  return (
    <a className={className} href={`tel:${business.phone.e164}`} data-track="phone_click" data-cta-location={location}>
      {business.phone.display}
    </a>
  );
}

export function EmailLink({ className, location }: { className?: string; location: string }) {
  if (!business.email) return <Todo label="business email in src/data/business.ts" />;
  return (
    <a className={className} href={`mailto:${business.email}`} data-track="email_click" data-cta-location={location}>
      {business.email}
    </a>
  );
}

/**
 * The ONE NAP block. Used in the footer (every page) and on /contact so
 * name, address and phone are identical sitewide.
 */
export function NapBlock({ location }: { location: string }) {
  const a = business.address;
  return (
    <div className="nap" data-nap="">
      <p className="nap-name">
        <strong>{business.name}</strong>
      </p>
      <p className="nap-address">
        {a.isPublic && a.streetAddress ? (
          <>
            {a.streetAddress}
            <br />
            {a.locality} {a.region} {a.postcode}
          </>
        ) : (
          <>
            {a.locality}, {a.region} — service-area business
          </>
        )}
      </p>
      <p className="nap-phone">
        Phone: <PhoneLink location={location} />
      </p>
      <p className="nap-email">
        Email: <EmailLink location={location} />
      </p>
      <p className="nap-hours">
        Hours:{' '}
        {business.hours?.length
          ? business.hours.map((h) => `${h.days.map((d) => d.slice(0, 3)).join(', ')} ${h.opens}–${h.closes}`).join('; ')
          : business.hoursNote}
      </p>
      {business.abn ? <p className="nap-abn">ABN {business.abn}</p> : null}
    </div>
  );
}
