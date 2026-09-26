import { siteConfig } from '../config';
import { captureUtm, loadGa, track } from '../lib/analytics';

/**
 * Wires up page-level analytics:
 * - page_view (+ package_view / location_page_view from body data attributes)
 * - delegated clicks: tel: → phone_click, mailto: → email_click,
 *   [data-track] → named event, [data-consultation] → consultation_click,
 *   [data-cta] → cta_click
 * No personal information is ever included.
 */
export function initAnalytics(): void {
  captureUtm(window.location.search);
  loadGa(siteConfig.gaMeasurementId);

  const b = document.body.dataset;
  const pageType = b.pageType ?? 'unknown';
  track('page_view', { page_path: window.location.pathname, page_type: pageType });
  if (pageType === 'package' && b.package) track('package_view', { package: b.package });
  if (pageType === 'location' && b.region) track('location_page_view', { region: b.region, tier: b.tier });

  document.addEventListener('click', (e) => {
    const target = e.target as Element | null;
    const a = target?.closest<HTMLElement>('a, button');
    if (!a) return;
    const href = a.getAttribute('href') ?? '';
    const loc = a.dataset.ctaLocation ?? pageType;
    if (href.startsWith('tel:')) {
      track('phone_click', { cta_location: loc, page_type: pageType });
    } else if (href.startsWith('mailto:')) {
      track('email_click', { cta_location: loc, page_type: pageType });
    } else if (a.dataset.track === 'directions_click') {
      track('directions_click', { page_type: pageType });
    }
    if (a.dataset.consultation) {
      track('consultation_click', { mode: a.dataset.consultation, cta_location: loc });
    }
    if (a.dataset.cta) {
      track('cta_click', { cta: a.dataset.cta, page_type: pageType, region: b.region });
    }
  });
}
