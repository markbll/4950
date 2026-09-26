import { useEffect, useState, type FormEvent } from 'react';
import { AU_STATES, isValidAuPhone, isValidEmail, maxLen, required, type Errors } from '../lib/validation';
import { track } from '../lib/analytics';
import { ErrorSummary, Field, Honeypot, MARKETING_CONSENT_LABEL, postJson, useForm, useFormToken } from './formKit';

const P = 'contact';

const LABELS = {
  name: 'Your name',
  email: 'Email',
  suburb: 'Suburb or town',
  state: 'State',
  message: 'How can we help?',
};

export default function ContactForm() {
  const token = useFormToken();
  const { values, set } = useForm({
    name: '',
    business: '',
    email: '',
    phone: '',
    suburb: '',
    state: 'VIC',
    meeting: 'either',
    message: '',
    marketing: false,
    company_fax: '',
  });
  const [errors, setErrors] = useState<Errors>({});
  const [message, setMessage] = useState<string | undefined>();
  const [status, setStatus] = useState<'idle' | 'sending' | 'done'>('idle');

  // Pre-select meeting type from ?meeting=in_person|video (after hydration to avoid mismatch).
  useEffect(() => {
    const m = new URLSearchParams(window.location.search).get('meeting');
    if (m === 'in_person' || m === 'video') set('meeting', m);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const errs: Errors = {};
    required(values, LABELS, errs);
    if (values.email && !errs.email && !isValidEmail(values.email)) errs.email = 'Enter a valid email address, like name@example.com.au.';
    if (values.phone && !isValidAuPhone(values.phone)) errs.phone = 'Enter a valid Australian phone number, like 0400 000 000.';
    maxLen(values, { name: 100, business: 150, suburb: 80, message: 3000 }, errs);
    setErrors(errs);
    setMessage(undefined);
    if (Object.keys(errs).length) return;
    setStatus('sending');
    const res = await postJson<{ tier: string }>('/api/contact.php', values, token);
    if (res.ok) {
      setStatus('done');
      track('contact_submit', { tier: res.data?.tier, mode: values.meeting });
    } else {
      setStatus('idle');
      setErrors(res.errors ?? {});
      setMessage(res.message);
    }
  }

  if (status === 'done') {
    return (
      <div className="form-success" role="status">
        <h3>Thanks, {values.name.split(' ')[0]} — we have your message.</h3>
        <p>We will be in touch soon to arrange a time to talk.</p>
      </div>
    );
  }

  const inPersonNote = values.state !== 'VIC' && values.meeting === 'in_person';

  return (
    <form className="form" noValidate onSubmit={onSubmit} aria-label="Contact Big Cat Marketing">
      <ErrorSummary errors={errors} message={message} idPrefix={P} />
      <div className="form-grid">
        <Field name="name" label={LABELS.name} error={errors.name} required idPrefix={P}>
          {(a) => <input {...a} name="name" autoComplete="name" maxLength={100} value={values.name} onChange={(e) => set('name', e.target.value)} />}
        </Field>
        <Field name="business" label="Business name" error={errors.business} idPrefix={P}>
          {(a) => (
            <input {...a} name="business" autoComplete="organization" maxLength={150} value={values.business} onChange={(e) => set('business', e.target.value)} />
          )}
        </Field>
        <Field name="email" label={LABELS.email} error={errors.email} required idPrefix={P}>
          {(a) => (
            <input {...a} type="email" name="email" autoComplete="email" maxLength={254} value={values.email} onChange={(e) => set('email', e.target.value)} />
          )}
        </Field>
        <Field name="phone" label="Phone" error={errors.phone} idPrefix={P}>
          {(a) => <input {...a} type="tel" name="phone" autoComplete="tel" maxLength={20} value={values.phone} onChange={(e) => set('phone', e.target.value)} />}
        </Field>
        <Field name="suburb" label={LABELS.suburb} error={errors.suburb} required idPrefix={P}>
          {(a) => (
            <input {...a} name="suburb" autoComplete="address-level2" maxLength={80} value={values.suburb} onChange={(e) => set('suburb', e.target.value)} />
          )}
        </Field>
        <Field name="state" label={LABELS.state} error={errors.state} required idPrefix={P}>
          {(a) => (
            <select {...a} name="state" autoComplete="address-level1" value={values.state} onChange={(e) => set('state', e.target.value)}>
              {AU_STATES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          )}
        </Field>
      </div>
      <fieldset className="field fieldset-radios">
        <legend>How would you like to meet?</legend>
        {[
          ['either', 'Whatever suits'],
          ['in_person', 'In person (Greater Melbourne)'],
          ['video', 'Video call'],
        ].map(([value, label]) => (
          <div className="radio" key={value}>
            <input
              type="radio"
              id={`${P}-meeting-${value}`}
              name="meeting"
              value={value}
              checked={values.meeting === value}
              onChange={() => set('meeting', value!)}
            />
            <label htmlFor={`${P}-meeting-${value}`}>{label}</label>
          </div>
        ))}
        {inPersonNote ? <p className="hint">Outside Victoria we meet by video. In regional Victoria, in person is by arrangement.</p> : null}
      </fieldset>
      <Field name="message" label={LABELS.message} error={errors.message} required idPrefix={P}>
        {(a) => <textarea {...a} name="message" rows={5} maxLength={3000} value={values.message} onChange={(e) => set('message', e.target.value)} />}
      </Field>
      <div className="field field-check">
        <input id={`${P}-marketing`} type="checkbox" name="marketing" checked={values.marketing} onChange={(e) => set('marketing', e.target.checked)} />
        <label htmlFor={`${P}-marketing`}>{MARKETING_CONSENT_LABEL}</label>
      </div>
      <p className="form-note">
        We use your details to respond to your enquiry. See our <a href="/privacy">Privacy Policy</a>.
      </p>
      <Honeypot idPrefix={P} value={values.company_fax} onChange={(v) => set('company_fax', v)} />
      <button type="submit" className="btn btn-primary" disabled={status === 'sending'}>
        {status === 'sending' ? 'Sending…' : 'Send message'}
      </button>
    </form>
  );
}
