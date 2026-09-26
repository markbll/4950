import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { Errors } from '../lib/validation';
import { getUtm } from '../lib/analytics';

export interface ApiResult<T = unknown> {
  ok: boolean;
  data?: T;
  errors?: Errors;
  message?: string;
}

interface TokenState {
  current: string | null;
  issuedAt?: number;
}

/** Server rejects tokens younger than 2s (bot timing check). */
const TOKEN_MIN_AGE_MS = 2100;

async function fetchToken(ref: TokenState): Promise<void> {
  const res = await fetch('/api/token.php', { headers: { Accept: 'application/json' }, credentials: 'same-origin' });
  if (!res.ok) throw new Error('token');
  const json = (await res.json()) as { token?: string };
  if (!json.token) throw new Error('token');
  ref.current = json.token;
  ref.issuedAt = Date.now();
}

/** Fetches a signed form token on mount (anti-CSRF / anti-bot timing). */
export function useFormToken(): TokenState {
  const [token] = useState<TokenState>(() => ({ current: null }));
  useEffect(() => {
    fetchToken(token).catch(() => {
      token.current = null;
    });
  }, [token]);
  return token;
}

export async function postJson<T>(endpoint: string, payload: Record<string, unknown>, tokenRef: TokenState): Promise<ApiResult<T>> {
  try {
    if (!tokenRef.current) await fetchToken(tokenRef);
    // Very fast submissions (autofill) wait out the server's minimum token age instead of failing.
    const age = Date.now() - (tokenRef.issuedAt ?? 0);
    if (age < TOKEN_MIN_AGE_MS) await new Promise((r) => setTimeout(r, TOKEN_MIN_AGE_MS - age));
    const res = await fetch(endpoint, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-Requested-With': 'fetch',
        'X-Form-Token': tokenRef.current ?? '',
      },
      body: JSON.stringify({ ...payload, utm: getUtm() }),
    });
    const json = (await res.json().catch(() => ({}))) as ApiResult<T>;
    if (res.status === 429) {
      return { ok: false, message: 'Too many attempts. Please wait a few minutes and try again.' };
    }
    if (!res.ok || !json.ok) {
      tokenRef.current = null; // fetch a fresh one next time
      return { ok: false, errors: json.errors, message: json.message ?? 'Something went wrong. Please try again.' };
    }
    return json;
  } catch {
    return { ok: false, message: 'We could not send your details. Please check your connection and try again.' };
  }
}

export function ErrorSummary({ errors, message, idPrefix }: { errors: Errors; message?: string; idPrefix: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const keys = Object.keys(errors);
  useEffect(() => {
    if (keys.length || message) ref.current?.focus();
  }, [keys.length, message]);
  if (!keys.length && !message) return null;
  return (
    <div className="error-summary" role="alert" tabIndex={-1} ref={ref}>
      <h3 className="error-summary-title">{keys.length ? 'Please check the following:' : 'There was a problem'}</h3>
      {message ? <p>{message}</p> : null}
      {keys.length ? (
        <ul>
          {keys.map((k) => (
            <li key={k}>
              <a href={`#${idPrefix}-${k}`}>{errors[k]}</a>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

interface FieldProps {
  name: string;
  label: string;
  error?: string;
  hint?: string;
  required?: boolean;
  children: (a11y: { id: string; 'aria-invalid'?: true; 'aria-describedby'?: string; required?: boolean }) => ReactNode;
  idPrefix?: string;
}

export function Field({ name, label, error, hint, required, children, idPrefix = 'f' }: FieldProps) {
  const id = `${idPrefix}-${name}`;
  const describedBy = [hint ? `${id}-hint` : '', error ? `${id}-error` : ''].filter(Boolean).join(' ') || undefined;
  return (
    <div className={`field${error ? ' field-error' : ''}`}>
      <label htmlFor={id}>
        {label}
        {required ? <span className="req"> (required)</span> : <span className="opt"> (optional)</span>}
      </label>
      {hint ? (
        <p className="hint" id={`${id}-hint`}>
          {hint}
        </p>
      ) : null}
      {error ? (
        <p className="error-text" id={`${id}-error`}>
          {error}
        </p>
      ) : null}
      {children({ id, 'aria-invalid': error ? true : undefined, 'aria-describedby': describedBy, required })}
    </div>
  );
}

/** Off-screen honeypot. Real users never see or fill it. */
export function Honeypot({ value, onChange, idPrefix }: { value: string; onChange: (v: string) => void; idPrefix: string }) {
  return (
    <div className="hp" aria-hidden="true">
      <label htmlFor={`${idPrefix}-hp`}>Leave this field empty</label>
      <input
        id={`${idPrefix}-hp`}
        name="company_fax"
        type="text"
        tabIndex={-1}
        autoComplete="off"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  );
}

export function useForm<T extends Record<string, unknown>>(initial: T) {
  const [values, setValues] = useState<T>(initial);
  const set = <K extends keyof T>(k: K, v: T[K]) => setValues((prev) => ({ ...prev, [k]: v }));
  return { values, set, setValues };
}

export const MARKETING_CONSENT_LABEL =
  'Yes, send me occasional local marketing tips and offers from Big Cat Marketing by email. I can unsubscribe at any time.';
