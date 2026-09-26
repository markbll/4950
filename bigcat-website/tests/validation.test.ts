import { describe, expect, it } from 'vitest';
import { isValidAuPhone, isValidEmail, isValidWebsite, normaliseWebsite, required } from '../src/lib/validation';

describe('client validation', () => {
  it('accepts Australian phone formats', () => {
    for (const p of ['0412 345 678', '(03) 9123 4567', '+61 3 9123 4567', '1300 123 456', '1800-123-456', '13 12 34']) {
      expect(isValidAuPhone(p), p).toBe(true);
    }
  });
  it('rejects bad phones', () => {
    for (const p of ['12345', '0912 345 678', 'abc', '']) expect(isValidAuPhone(p), p).toBe(false);
  });
  it('validates email', () => {
    expect(isValidEmail('owner@example.com.au')).toBe(true);
    expect(isValidEmail('nope')).toBe(false);
    expect(isValidEmail('a@b')).toBe(false);
  });
  it('validates and normalises websites', () => {
    expect(normaliseWebsite('example.com.au')).toBe('https://example.com.au');
    expect(isValidWebsite('example.com.au')).toBe(true);
    expect(isValidWebsite('')).toBe(true);
    expect(isValidWebsite('javascript:alert(1)')).toBe(false);
    expect(isValidWebsite('not a url')).toBe(false);
  });
  it('flags required fields including unticked consent', () => {
    const errs: Record<string, string> = {};
    required({ a: '', b: 'x', c: false }, { a: 'A', b: 'B', c: 'C' }, errs);
    expect(Object.keys(errs)).toEqual(['a', 'c']);
  });
});
