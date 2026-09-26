// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import CheckupForm from '../src/islands/CheckupForm';

const props = { industryOptions: [{ value: 'trades', label: 'Trades' }], serviceOptions: ['Local SEO'] };

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('CheckupForm', () => {
  it('shows an accessible error summary when step 1 is incomplete', () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ token: 'x' })));
    render(<CheckupForm {...props} />);
    fireEvent.click(screen.getByRole('button', { name: 'Next' }));
    const alert = screen.getByRole('alert');
    expect(alert.textContent).toContain('Business name is required.');
    expect(screen.getByLabelText(/Business name/)).toHaveProperty('ariaInvalid', 'true');
  });

  it('advances through the steps once fields are valid', () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ token: 'x' })));
    render(<CheckupForm {...props} />);
    fireEvent.change(screen.getByLabelText(/Business name/), { target: { value: 'Acme' } });
    fireEvent.change(screen.getByLabelText(/Suburb or town/), { target: { value: 'Coburg' } });
    fireEvent.change(screen.getByLabelText(/Industry/), { target: { value: 'trades' } });
    fireEvent.click(screen.getByRole('button', { name: 'Next' }));
    expect(screen.getByRole('heading', { level: 2 }).textContent).toContain('Step 2 of 3');
  });
});
