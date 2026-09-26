import { useRef, useState, type FormEvent } from 'react';
import { AU_STATES, isValidAuPhone, isValidEmail, isValidWebsite, maxLen, required, type Errors } from '../lib/validation';
import { track } from '../lib/analytics';
import { ErrorSummary, Field, Honeypot, MARKETING_CONSENT_LABEL, postJson, useForm, useFormToken } from './formKit';

const P = 'chk';

export interface CheckupFinding {
  label: string;
  result: 'found' | 'missing' | 'info';
  detail?: string;
}

export interface CheckupCategory {
  key: string;
  label: string;
  status: 'checked' | 'team_review' | 'not_checked';
  summary: string;
  findings?: CheckupFinding[];
}

export interface CheckupResponse {
  tier: 'melbourne' | 'regional_vic' | 'remote';
  reference: string;
  categories: CheckupCategory[];
}

const STEPS = ['Your business', 'Your area and services', 'Your details'] as const;

const LABELS: Record<string, string> = {
  businessName: 'Business name',
  suburb: 'Suburb or town',
  state: 'State',
  industry: 'Industry',
  mainServiceArea: 'Main service area',
  primaryService: 'Primary service',
  contactName: 'Your name',
  email: 'Email',
  phone: 'Phone',
  consent: 'Consent',
};

const STEP_FIELDS: string[][] = [
  ['businessName', 'website', 'suburb', 'state', 'industry'],
  ['mainServiceArea', 'primaryService', 'budget', 'challenge'],
  ['contactName', 'email', 'phone', 'consent'],
];

const STATUS_TEXT: Record<CheckupCategory['status'], string> = {
  checked: 'Checked automatically',
  team_review: 'Reviewed by our team within 1 business day',
  not_checked: 'Not checked',
};

const TIER_TEXT: Record<CheckupResponse['tier'], string> = {
  melbourne: 'You are in Greater Melbourne — we can meet in person or by video.',
  regional_vic: 'You are in regional Victoria — we will meet by video, or in person by arrangement.',
  remote: 'You are outside Victoria — we will work with you fully remotely by video.',
};

export interface CheckupFormProps {
  industryOptions: { value: string; label: string }[];
  serviceOptions: string[];
}

export default function CheckupForm({ industryOptions, serviceOptions }: CheckupFormProps) {
  const token = useFormToken();
  const started = useRef(false);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [step, setStep] = useState(0);
  const [errors, setErrors] = useState<Errors>({});
  const [message, setMessage] = useState<string | undefined>();
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState<CheckupResponse | null>(null);
  const { values, set } = useForm({
    businessName: '',
    website: '',
    suburb: '',
    state: 'VIC',
    industry: '',
    mainServiceArea: '',
    primaryService: '',
    budget: '',
    challenge: '',
    contactName: '',
    email: '',
    phone: '',
    consent: false,
    marketing: false,
    company_fax: '',
  });

  function markStarted() {
    if (!started.current) {
      started.current = true;
      track('checkup_start', { step: 1 });
    }
  }

  function validate(s: number): Errors {
    const errs: Errors = {};
    const fields = Object.fromEntries(STEP_FIELDS[s]!.filter((f) => LABELS[f]).map((f) => [f, LABELS[f]!]));
    required(values, fields, errs);
    if (s === 0 && values.website && !isValidWebsite(values.website)) errs.website = 'Enter a website address like example.com.au.';
    if (s === 2) {
      if (values.email && !errs.email && !isValidEmail(values.email)) errs.email = 'Enter a valid email address, like name@example.com.au.';
      if (values.phone && !errs.phone && !isValidAuPhone(values.phone)) errs.phone = 'Enter a valid Australian phone number, like 0400 000 000.';
      if (!values.consent) errs.consent = 'Please agree so we can send you your check-up.';
    }
    maxLen(values, { businessName: 150, suburb: 80, mainServiceArea: 150, primaryService: 150, challenge: 1500, contactName: 100 }, errs);
    return errs;
  }

  function focusHeading() {
    requestAnimationFrame(() => headingRef.current?.focus());
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const errs = validate(step);
    setErrors(errs);
    setMessage(undefined);
    if (Object.keys(errs).length) return;
    if (step < STEPS.length - 1) {
      setStep(step + 1);
      focusHeading();
      return;
    }
    setSending(true);
    const res = await postJson<CheckupResponse>('/api/checkup.php', values, token);
    setSending(false);
    if (res.ok && res.data) {
      setResult(res.data);
      track('checkup_complete', { tier: res.data.tier, industry: values.industry });
      track('lead_submit', { tier: res.data.tier, cta_location: 'checkup' });
      focusHeading();
    } else {
      const serverErrors = res.errors ?? {};
      setErrors(serverErrors);
      setMessage(res.message);
      const first = STEP_FIELDS.findIndex((fs) => fs.some((f) => serverErrors[f]));
      if (first >= 0 && first !== step) setStep(first);
    }
  }

  if (result) {
    return (
      <div className="checkup-results">
        <h2 ref={headingRef} tabIndex={-1}>
          Your local visibility check-up
        </h2>
        <p>
          Thanks, {values.contactName.split(' ')[0]}. Here is what we could check straight away for <strong>{values.businessName}</strong>.
          Everything else is reviewed by a person on our team — we never guess or invent a score.
        </p>
        <p className="tier-note">{TIER_TEXT[result.tier]}</p>
        <p className="form-note">Reference: {result.reference}</p>
        <ul className="result-list">
          {result.categories.map((c) => (
            <li key={c.key} className={`result result-${c.status}`}>
              <h3>{c.label}</h3>
              <p className="result-status">{STATUS_TEXT[c.status]}</p>
              <p>{c.summary}</p>
              {c.findings?.length ? (
                <ul className="findings">
                  {c.findings.map((f) => (
                    <li key={f.label} className={`finding finding-${f.result}`}>
                      <span className="finding-label">
                        {f.result === 'found' ? 'Found: ' : f.result === 'missing' ? 'Not found: ' : 'Note: '}
                        {f.label}
                      </span>
                      {f.detail ? <span className="finding-detail"> — {f.detail}</span> : null}
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
        <div className="actions">
          <a className="btn btn-primary" href="/contact" data-cta="checkup_results_talk">
            Talk to Big Cat Marketing
          </a>
          <a className="btn btn-secondary" href="/packages" data-cta="checkup_results_packages">
            View Our Packages
          </a>
        </div>
      </div>
    );
  }

  const input = (name: keyof typeof values, extra: Record<string, unknown> = {}) => (a: Record<string, unknown>) => (
    <input
      {...a}
      {...extra}
      name={name}
      value={values[name] as string}
      onFocus={markStarted}
      onChange={(e) => set(name, e.target.value)}
    />
  );

  return (
    <form className="form checkup-form" noValidate onSubmit={onSubmit} aria-labelledby={`${P}-step-heading`}>
      <ol className="steps" aria-label="Progress">
        {STEPS.map((s, i) => (
          <li key={s} className={i === step ? 'step-current' : i < step ? 'step-done' : ''} aria-current={i === step ? 'step' : undefined}>
            <span className="step-num">{i + 1}</span> {s}
          </li>
        ))}
      </ol>
      <h2 id={`${P}-step-heading`} ref={headingRef} tabIndex={-1} className="step-heading">
        Step {step + 1} of {STEPS.length}: {STEPS[step]}
      </h2>
      <ErrorSummary errors={errors} message={message} idPrefix={P} />

      {step === 0 ? (
        <div className="form-grid">
          <Field name="businessName" label={LABELS.businessName!} error={errors.businessName} required idPrefix={P}>
            {input('businessName', { autoComplete: 'organization', maxLength: 150 })}
          </Field>
          <Field name="website" label="Website" hint="If you have one, e.g. example.com.au" error={errors.website} idPrefix={P}>
            {input('website', { type: 'url', inputMode: 'url', autoComplete: 'url', maxLength: 300 })}
          </Field>
          <Field name="suburb" label={LABELS.suburb!} error={errors.suburb} required idPrefix={P}>
            {input('suburb', { autoComplete: 'address-level2', maxLength: 80 })}
          </Field>
          <Field name="state" label={LABELS.state!} error={errors.state} required idPrefix={P}>
            {(a) => (
              <select {...a} name="state" value={values.state} onFocus={markStarted} onChange={(e) => set('state', e.target.value)}>
                {AU_STATES.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            )}
          </Field>
          <Field name="industry" label={LABELS.industry!} error={errors.industry} required idPrefix={P}>
            {(a) => (
              <select {...a} name="industry" value={values.industry} onFocus={markStarted} onChange={(e) => set('industry', e.target.value)}>
                <option value="">Choose one</option>
                {industryOptions.map((i) => (
                  <option key={i.value} value={i.value}>
                    {i.label}
                  </option>
                ))}
                <option value="other">Other</option>
              </select>
            )}
          </Field>
        </div>
      ) : null}

      {step === 1 ? (
        <div className="form-grid">
          <Field
            name="mainServiceArea"
            label={LABELS.mainServiceArea!}
            hint="The suburbs, region or town you most want customers from"
            error={errors.mainServiceArea}
            required
            idPrefix={P}
          >
            {input('mainServiceArea', { maxLength: 150 })}
          </Field>
          <Field name="primaryService" label={LABELS.primaryService!} hint="What you most want to be found for, e.g. “emergency plumbing”" error={errors.primaryService} required idPrefix={P}>
            {input('primaryService', { maxLength: 150, list: `${P}-service-suggestions` })}
          </Field>
          <datalist id={`${P}-service-suggestions`}>
            {serviceOptions.map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
          <Field name="budget" label="Monthly marketing budget" error={errors.budget} idPrefix={P}>
            {(a) => (
              <select {...a} name="budget" value={values.budget} onChange={(e) => set('budget', e.target.value)}>
                <option value="">Prefer not to say</option>
                <option value="under-500">Under $500</option>
                <option value="500-1000">$500–$1,000</option>
                <option value="1000-2000">$1,000–$2,000</option>
                <option value="2000-plus">$2,000+</option>
                <option value="unsure">Not sure yet</option>
              </select>
            )}
          </Field>
          <Field name="challenge" label="Your biggest marketing challenge" error={errors.challenge} idPrefix={P}>
            {(a) => <textarea {...a} name="challenge" rows={4} maxLength={1500} value={values.challenge} onChange={(e) => set('challenge', e.target.value)} />}
          </Field>
        </div>
      ) : null}

      {step === 2 ? (
        <div className="form-grid">
          <Field name="contactName" label={LABELS.contactName!} error={errors.contactName} required idPrefix={P}>
            {input('contactName', { autoComplete: 'name', maxLength: 100 })}
          </Field>
          <Field name="email" label={LABELS.email!} error={errors.email} required idPrefix={P}>
            {input('email', { type: 'email', autoComplete: 'email', maxLength: 254 })}
          </Field>
          <Field name="phone" label={LABELS.phone!} error={errors.phone} required idPrefix={P}>
            {input('phone', { type: 'tel', autoComplete: 'tel', maxLength: 20 })}
          </Field>
          <div className={`field field-check field-wide${errors.consent ? ' field-error' : ''}`}>
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
              I agree to Big Cat Marketing contacting me by email or phone about my check-up. (required)
            </label>
          </div>
          <div className="field field-check field-wide">
            <input id={`${P}-marketing`} type="checkbox" name="marketing" checked={values.marketing} onChange={(e) => set('marketing', e.target.checked)} />
            <label htmlFor={`${P}-marketing`}>{MARKETING_CONSENT_LABEL}</label>
          </div>
          <p className="form-note field-wide">
            If you give us a website, we will fetch its public home page once to check for local signals. See our <a href="/privacy">Privacy Policy</a>.
          </p>
        </div>
      ) : null}

      <Honeypot idPrefix={P} value={values.company_fax} onChange={(v) => set('company_fax', v)} />
      <div className="actions">
        {step > 0 ? (
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => {
              setErrors({});
              setStep(step - 1);
              focusHeading();
            }}
          >
            Back
          </button>
        ) : null}
        <button type="submit" className="btn btn-primary" disabled={sending}>
          {sending ? 'Checking… this can take up to 20 seconds' : step < STEPS.length - 1 ? 'Next' : 'Get my check-up'}
        </button>
      </div>
    </form>
  );
}
