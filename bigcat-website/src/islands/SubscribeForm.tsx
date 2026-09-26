import { useState, type FormEvent } from 'react';
import { isValidEmail, type Errors } from '../lib/validation';
import { track } from '../lib/analytics';
import { ErrorSummary, Field, Honeypot, postJson, useForm, useFormToken } from './formKit';

const P = 'sub';

export default function SubscribeForm() {
  const token = useFormToken();
  const { values, set } = useForm({ email: '', consent: false, company_fax: '' });
  const [errors, setErrors] = useState<Errors>({});
  const [message, setMessage] = useState<string | undefined>();
  const [status, setStatus] = useState<'idle' | 'sending' | 'done'>('idle');

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const errs: Errors = {};
    if (!isValidEmail(values.email)) errs.email = 'Enter a valid email address.';
    if (!values.consent) errs.consent = 'Please tick the box to confirm you want to receive emails.';
    setErrors(errs);
    setMessage(undefined);
    if (Object.keys(errs).length) return;
    setStatus('sending');
    const res = await postJson('/api/subscribe.php', values, token);
    if (res.ok) {
      setStatus('done');
      track('subscribe_submit', { cta_location: 'footer' });
    } else {
      setStatus('idle');
      setErrors(res.errors ?? {});
      setMessage(res.message);
    }
  }

  if (status === 'done') {
    return (
      <p className="form-success" role="status">
        Thanks — you are subscribed. Every email includes an unsubscribe link.
      </p>
    );
  }

  return (
    <form className="subscribe-form" noValidate onSubmit={onSubmit} aria-label="Subscribe to local marketing tips">
      <ErrorSummary errors={errors} message={message} idPrefix={P} />
      <Field name="email" label="Email" error={errors.email} required idPrefix={P}>
        {(a) => (
          <input
            {...a}
            type="email"
            name="email"
            autoComplete="email"
            maxLength={254}
            value={values.email}
            onChange={(e) => set('email', e.target.value)}
          />
        )}
      </Field>
      <div className={`field field-check${errors.consent ? ' field-error' : ''}`}>
        {errors.consent ? (
          <p className="error-text" id={`${P}-consent-error`}>
            {errors.consent}
          </p>
        ) : null}
        <input
          id={`${P}-consent`}
          type="checkbox"
          name="consent"
          checked={values.consent}
          aria-invalid={errors.consent ? true : undefined}
          aria-describedby={errors.consent ? `${P}-consent-error` : undefined}
          onChange={(e) => set('consent', e.target.checked)}
        />
        <label htmlFor={`${P}-consent`}>
          I agree to receive occasional marketing emails from Big Cat Marketing. I can unsubscribe at any time. See our{' '}
          <a href="/privacy">Privacy Policy</a>.
        </label>
      </div>
      <Honeypot idPrefix={P} value={values.company_fax} onChange={(v) => set('company_fax', v)} />
      <button type="submit" className="btn btn-primary" disabled={status === 'sending'}>
        {status === 'sending' ? 'Subscribing…' : 'Subscribe'}
      </button>
    </form>
  );
}
