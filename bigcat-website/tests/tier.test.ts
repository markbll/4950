import { describe, expect, it } from 'vitest';
import fixtures from '../shared/tier-fixtures.json';
import { tierFor } from '../src/lib/tier';

describe('lead tier tagging', () => {
  for (const c of fixtures.cases) {
    it(`${c.suburb} / ${c.state} → ${c.tier}`, () => {
      expect(tierFor(c.suburb, c.state)).toBe(c.tier);
    });
  }
});
