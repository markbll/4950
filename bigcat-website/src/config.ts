/**
 * Build-time site configuration. Values come from VITE_* environment
 * variables (see .env.example). Nothing secret belongs here — every value
 * is compiled into public HTML/JS.
 */
export type SiteEnv = 'development' | 'staging' | 'production';

const rawEnv = (import.meta.env.VITE_SITE_ENV ?? 'development') as string;

export const siteConfig = {
  /** Canonical origin. Defaults to production so canonicals are stable across staging and production. */
  siteUrl: ((import.meta.env.VITE_SITE_URL as string | undefined) ?? 'https://bigcatmarketing.com.au').replace(/\/+$/, ''),
  env: (['development', 'staging', 'production'].includes(rawEnv) ? rawEnv : 'development') as SiteEnv,
  /** GA4 measurement ID (public). Leave empty to disable analytics script loading. */
  gaMeasurementId: (import.meta.env.VITE_GA_MEASUREMENT_ID as string | undefined) ?? '',
};

/** Anything that is not production must never be indexed. */
export const isIndexable = siteConfig.env === 'production';
/** TODO markers are rendered visibly everywhere except production. */
export const showTodoMarkers = siteConfig.env !== 'production';
