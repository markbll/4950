import localities from '../../shared/greater-melbourne-localities.json';
import type { ServiceTier } from '../data/business';

const MELBOURNE = new Set(localities.localities);

export { AU_STATES, type AuState } from './validation';

export function normaliseLocality(value: string): string {
  return value
    .toLowerCase()
    .replace(/\b(vic|victoria)\b/g, '')
    .replace(/\b\d{4}\b/g, '')
    .replace(/[^a-z\s'-]/g, ' ')
    .replace(/\bst\.?\s/g, 'st ')
    .replace(/\bmt\.?\s/g, 'mount ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Lead tier from suburb/town + state. Mirrors api/lib/tier.php — keep in sync
 * (tests/tier.test.ts and api/tests/run.php use the same fixtures).
 */
export function tierFor(suburb: string, state: string): ServiceTier {
  const s = state.trim().toUpperCase();
  if (s !== 'VIC' && s !== 'VICTORIA') return 'remote';
  const locality = normaliseLocality(suburb);
  if (MELBOURNE.has(locality)) return 'melbourne';
  return 'regional_vic';
}
