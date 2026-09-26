/**
 * Privacy-safe analytics. Events go to window.dataLayer (GTM/GA4 compatible)
 * and, if VITE_GA_MEASUREMENT_ID is set, to gtag.
 *
 * RULE: no personal information in events. sanitiseParams() enforces an
 * allow-list of parameter names and drops anything that looks like an email
 * address or phone number.
 */
export type AnalyticsEvent =
  | 'page_view'
  | 'package_view'
  | 'location_page_view'
  | 'checkup_start'
  | 'checkup_complete'
  | 'lead_submit'
  | 'contact_submit'
  | 'subscribe_submit'
  | 'consultation_click'
  | 'phone_click'
  | 'email_click'
  | 'directions_click'
  | 'cta_click';

const ALLOWED_PARAMS = new Set([
  'page_path',
  'page_type',
  'package',
  'region',
  'tier',
  'mode',
  'cta',
  'cta_location',
  'step',
  'industry',
  'utm_source',
  'utm_medium',
  'utm_campaign',
]);

const EMAIL_LIKE = /[^\s@]+@[^\s@]+/;
const PHONE_LIKE = /(?:\+?\d[\s-]?){8,}/;

export type Params = Record<string, string | number | undefined>;

export function sanitiseParams(params: Params): Record<string, string | number> {
  const out: Record<string, string | number> = {};
  for (const [k, v] of Object.entries(params)) {
    if (!ALLOWED_PARAMS.has(k) || v === undefined || v === '') continue;
    if (typeof v === 'string') {
      if (EMAIL_LIKE.test(v) || PHONE_LIKE.test(v)) continue;
      out[k] = v.slice(0, 100);
    } else if (Number.isFinite(v)) {
      out[k] = v;
    }
  }
  return out;
}

const UTM_KEY = 'bc_utm';
const UTM_FIELDS = ['utm_source', 'utm_medium', 'utm_campaign'] as const;

/** Capture UTM params on landing; persisted for the session only. */
export function captureUtm(search: string): Record<string, string> {
  const params = new URLSearchParams(search);
  const found: Record<string, string> = {};
  for (const f of UTM_FIELDS) {
    const v = params.get(f);
    if (v) found[f] = v.replace(/[^\w.\- ]/g, '').slice(0, 60);
  }
  try {
    if (Object.keys(found).length) sessionStorage.setItem(UTM_KEY, JSON.stringify(found));
    else {
      const stored = sessionStorage.getItem(UTM_KEY);
      if (stored) return JSON.parse(stored) as Record<string, string>;
    }
  } catch {
    /* storage unavailable — fine */
  }
  return found;
}

export function getUtm(): Record<string, string> {
  try {
    const stored = sessionStorage.getItem(UTM_KEY);
    return stored ? (JSON.parse(stored) as Record<string, string>) : {};
  } catch {
    return {};
  }
}

type Gtag = (...args: unknown[]) => void;
declare global {
  interface Window {
    dataLayer?: unknown[];
    gtag?: Gtag;
  }
}

export function track(event: AnalyticsEvent, params: Params = {}): void {
  if (typeof window === 'undefined') return;
  const clean = sanitiseParams({ ...getUtm(), ...params });
  window.dataLayer = window.dataLayer ?? [];
  window.dataLayer.push({ event, ...clean });
  if (typeof window.gtag === 'function') window.gtag('event', event, clean);
}

export function loadGa(measurementId: string): void {
  if (!measurementId || !/^G-[A-Z0-9]+$/.test(measurementId)) return;
  window.dataLayer = window.dataLayer ?? [];
  window.gtag = function gtag() {
    // eslint-disable-next-line prefer-rest-params
    window.dataLayer!.push(arguments);
  };
  window.gtag('js', new Date());
  // page_view is sent manually so it carries our sanitised params.
  window.gtag('config', measurementId, { send_page_view: false, anonymize_ip: true });
  const s = document.createElement('script');
  s.async = true;
  s.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`;
  document.head.appendChild(s);
}
