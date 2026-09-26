import type { ReactNode } from 'react';
import { business } from '../data/business';
import { packages } from '../data/packages';
import { services } from '../data/services';
import { locations } from '../data/locations';
import { NapBlock } from './Nap';
import { Island } from './Island';
import SubscribeForm from '../islands/SubscribeForm';
import { CHECKUP_PATH } from '../constants';

export const NAV = [
  { label: 'Home', href: '/' },
  { label: 'Packages', href: '/packages' },
  { label: 'Services', href: '/services' },
  { label: 'Industries', href: '/industries' },
  { label: 'Locations', href: '/locations' },
  { label: 'Results', href: '/results' },
  { label: 'About', href: '/about' },
  { label: 'Contact', href: '/contact' },
];


function isActive(current: string, href: string): boolean {
  if (href === '/') return current === '/';
  return current === href || current.startsWith(`${href}/`);
}

/** Placeholder mark. TODO(asset): replace with the approved Big Cat Marketing logo. */
function LogoMark() {
  return (
    <svg className="logo-mark" viewBox="0 0 48 48" width="40" height="40" aria-hidden="true" focusable="false">
      <rect width="48" height="48" rx="12" fill="#0A0E1A" />
      <path d="M12 34V16l7 6h10l7-6v18c0 3-3 6-6 6H18c-3 0-6-3-6-6z" fill="#F59E0B" />
      <circle cx="19.5" cy="28" r="2" fill="#0A0E1A" />
      <circle cx="28.5" cy="28" r="2" fill="#0A0E1A" />
    </svg>
  );
}

function Header({ path }: { path: string }) {
  return (
    <header className="site-header">
      <div className="container header-inner">
        <a className="brand" href="/" aria-label={`${business.name} — home`}>
          <LogoMark />
          <span className="brand-name">{business.name}</span>
        </a>
        <nav id="site-nav" className="site-nav" aria-label="Main">
          <ul>
            {NAV.map((item) => (
              <li key={item.href}>
                <a href={item.href} aria-current={isActive(path, item.href) ? 'page' : undefined}>
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        <div className="header-actions">
          {business.phone ? (
            <a
              className="header-call"
              href={`tel:${business.phone.e164}`}
              data-track="phone_click"
              data-cta-location="header"
            >
              <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
                <path
                  fill="currentColor"
                  d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25 11.4 11.4 0 0 0 3.6.57 1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1z"
                />
              </svg>
              <span>Call</span>
            </a>
          ) : (
            <a className="header-call" href="/contact" data-cta="header_contact_no_phone">
              {/* TODO(fact): becomes click-to-call once business.phone is set */}
              <span>Call</span>
            </a>
          )}
          <a className="btn btn-primary header-cta" href={CHECKUP_PATH} data-cta="header_checkup">
            <span className="cta-long">Free Local Visibility Check-up</span>
            <span className="cta-short">Free Check-up</span>
          </a>
          <button type="button" className="menu-toggle" aria-expanded="false" aria-controls="site-nav" hidden>
            <span className="menu-toggle-bars" aria-hidden="true" />
            <span className="menu-toggle-label">Menu</span>
          </button>
        </div>
      </div>
    </header>
  );
}

function Footer() {
  const melb = locations.filter((l) => l.parent === 'melbourne');
  return (
    <footer className="site-footer">
      <div className="container footer-grid">
        <section className="footer-col footer-about" aria-labelledby="footer-nap-heading">
          <h2 id="footer-nap-heading" className="footer-heading">
            Contact details
          </h2>
          <NapBlock location="footer" />
          <p className="service-area-line">{business.serviceAreaLine}</p>
          <ul className="tier-list">
            {business.serviceAreas.map((t) => (
              <li key={t.tier}>
                <a href={`/locations/${t.locationSlug}`}>{t.label}</a> — {t.delivery.toLowerCase()}
              </li>
            ))}
          </ul>
        </section>
        <nav className="footer-col" aria-labelledby="footer-packages">
          <h2 id="footer-packages" className="footer-heading">
            Packages
          </h2>
          <ul>
            {packages.map((p) => (
              <li key={p.slug}>
                <a href={`/packages/${p.slug}`}>
                  {p.name} — {p.theme}
                </a>
              </li>
            ))}
            <li>
              <a href="/packages#custom">Big Cat Growth (custom)</a>
            </li>
          </ul>
          <h2 className="footer-heading footer-heading-spaced">Company</h2>
          <ul>
            <li>
              <a href="/about">About</a>
            </li>
            <li>
              <a href="/results">Results</a>
            </li>
            <li>
              <a href="/contact">Contact</a>
            </li>
            <li>
              <a href={CHECKUP_PATH}>Free Local Visibility Check-up</a>
            </li>
          </ul>
        </nav>
        <nav className="footer-col" aria-labelledby="footer-services">
          <h2 id="footer-services" className="footer-heading">
            Services
          </h2>
          <ul>
            {services.map((s) => (
              <li key={s.slug}>
                <a href={`/services/${s.slug}`}>{s.name}</a>
              </li>
            ))}
          </ul>
        </nav>
        <nav className="footer-col" aria-labelledby="footer-locations">
          <h2 id="footer-locations" className="footer-heading">
            Areas we serve
          </h2>
          <ul>
            <li>
              <a href="/locations/melbourne">Greater Melbourne</a>
            </li>
            {melb.map((l) => (
              <li key={l.slug}>
                <a href={l.path}>{l.shortName}</a>
              </li>
            ))}
            <li>
              <a href="/locations/regional-victoria">Geelong &amp; regional Victoria</a>
            </li>
            <li>
              <a href="/locations/australia">Australia-wide</a>
            </li>
          </ul>
        </nav>
        <section className="footer-col footer-subscribe" aria-labelledby="footer-subscribe-heading">
          <h2 id="footer-subscribe-heading" className="footer-heading">
            Local marketing tips
          </h2>
          <p>Occasional, practical tips for being found locally. No spam.</p>
          <Island name="subscribe" props={{}}>
            <SubscribeForm />
          </Island>
        </section>
      </div>
      <div className="container footer-bottom">
        <p>
          © {__BUILD_YEAR__} {business.legalName ?? business.name}. All prices ex GST.
        </p>
        <ul className="footer-legal">
          <li>
            <a href="/privacy">Privacy</a>
          </li>
          <li>
            <a href="/terms">Terms</a>
          </li>
          <li>
            <a href="/sitemap.xml">Sitemap</a>
          </li>
        </ul>
      </div>
    </footer>
  );
}

export function Layout({ path, children }: { path: string; children: ReactNode }) {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to main content
      </a>
      <Header path={path} />
      <main id="main" tabIndex={-1}>
        {children}
      </main>
      <Footer />
    </>
  );
}
