/**
 * Client-side validation rules. The PHP API re-validates everything —
 * these exist only to give fast, accessible feedback.
 */
export type Errors = Record<string, string>;

export const AU_STATES = ['VIC', 'NSW', 'QLD', 'SA', 'WA', 'TAS', 'ACT', 'NT'] as const;
export type AuState = (typeof AU_STATES)[number];

export const EMAIL_RE = /^[^\s@<>()[\]\\,;:"]+@[^\s@<>()[\]\\,;:"]+\.[a-z]{2,}$/i;
/** Australian phone numbers: landline, mobile, 13/1300/1800. Spaces, brackets and dashes allowed. */
export const AU_PHONE_RE = /^(?:\+?61|0)[2-478](?:[ -]?\d){8}$|^1[38]00(?:[ -]?\d){6}$|^13(?:[ -]?\d){4}$/;

export function normalisePhone(v: string): string {
  return v.replace(/[()\s.-]/g, '').replace(/^\+61/, '0').replace(/^61(?=[2-478]\d{8}$)/, '0');
}

export function isValidEmail(v: string): boolean {
  return v.length <= 254 && EMAIL_RE.test(v.trim());
}

export function isValidAuPhone(v: string): boolean {
  const compact = v.replace(/[()\s.-]/g, '');
  return AU_PHONE_RE.test(compact);
}

export function normaliseWebsite(v: string): string {
  const t = v.trim();
  if (!t) return '';
  return /^https?:\/\//i.test(t) ? t : `https://${t}`;
}

export function isValidWebsite(v: string): boolean {
  if (!v.trim()) return true;
  try {
    const u = new URL(normaliseWebsite(v));
    return (u.protocol === 'https:' || u.protocol === 'http:') && u.hostname.includes('.') && v.length <= 300;
  } catch {
    return false;
  }
}

export function required(values: Record<string, unknown>, fields: Record<string, string>, errors: Errors): void {
  for (const [field, label] of Object.entries(fields)) {
    const v = values[field];
    if (v === undefined || v === null || (typeof v === 'string' && v.trim() === '') || v === false) {
      errors[field] = `${label} is required.`;
    }
  }
}

export function maxLen(values: Record<string, unknown>, limits: Record<string, number>, errors: Errors): void {
  for (const [field, limit] of Object.entries(limits)) {
    const v = values[field];
    if (typeof v === 'string' && v.length > limit && !errors[field]) {
      errors[field] = `Please keep this under ${limit} characters.`;
    }
  }
}
