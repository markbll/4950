import { describe, expect, it } from 'vitest';
import { sanitiseParams } from '../src/lib/analytics';

describe('analytics sanitiser (no personal information)', () => {
  it('drops parameters that are not allow-listed', () => {
    expect(sanitiseParams({ email: 'a@b.com', name: 'Jo', phone: '0400000000', tier: 'melbourne' })).toEqual({ tier: 'melbourne' });
  });
  it('drops allow-listed values that look like emails or phone numbers', () => {
    expect(sanitiseParams({ cta: 'jo@example.com', region: '0412 345 678', package: 'gold' })).toEqual({ package: 'gold' });
  });
  it('keeps UTM params and truncates long values', () => {
    const out = sanitiseParams({ utm_source: 'google', utm_campaign: 'x'.repeat(200) });
    expect(out.utm_source).toBe('google');
    expect(String(out.utm_campaign).length).toBe(100);
  });
});
