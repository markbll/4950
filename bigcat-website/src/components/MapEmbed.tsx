import { business } from '../data/business';

/**
 * Lazy Google Map embed. SSR renders a lightweight placeholder; the client
 * script (src/client/map.ts) swaps in the iframe when it nears the viewport
 * or when the button is pressed. Uses a service-area query unless a public
 * address is approved in business.ts.
 */
export function MapEmbed({ title }: { title: string }) {
  const a = business.address;
  const q = a.isPublic && a.streetAddress ? `${business.name}, ${a.streetAddress}, ${a.locality} ${a.region} ${a.postcode ?? ''}` : business.mapQuery;
  const embed = `https://www.google.com/maps?q=${encodeURIComponent(q)}&output=embed`;
  const open = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
  return (
    <div className="map-embed" data-map-src={embed} data-map-title={title}>
      <div className="map-placeholder">
        <p>Map of {a.isPublic && a.streetAddress ? 'our location' : 'Melbourne, our home base'}.</p>
        <button type="button" className="btn btn-secondary map-load">
          Show map
        </button>
        <p className="map-note">Map provided by Google Maps. See our <a href="/privacy">Privacy Policy</a>.</p>
      </div>
      <p className="map-link">
        <a href={open} target="_blank" rel="noopener noreferrer" data-track="directions_click">
          Open in Google Maps<span className="visually-hidden"> (opens in a new tab)</span>
        </a>
      </p>
    </div>
  );
}
