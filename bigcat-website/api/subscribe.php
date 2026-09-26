<?php
/** POST /api/subscribe.php — newsletter opt-in (express consent, Spam Act 2003). */
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

$body = begin_form_request('subscribe', 5, 900);
if (is_bot($body)) {
    json_response(200, ['ok' => true]);
}

$email = clean_str($body['email'] ?? '', 254);
$consent = ($body['consent'] ?? false) === true;
$errors = [];
if (!valid_email($email)) {
    $errors['email'] = 'Enter a valid email address.';
}
if (!$consent) {
    $errors['consent'] = 'Please tick the box to confirm you want to receive emails.';
}
if ($errors) {
    fail(422, 'Please check the highlighted fields.', $errors);
}

$text = "New newsletter subscription (express consent given via website form).\n\n"
    . format_fields([
        'Email' => $email,
        'Consent wording' => 'I agree to receive occasional marketing emails from Big Cat Marketing. I can unsubscribe at any time.',
        'Consent time (UTC)' => gmdate('c'),
        'Source' => 'Website footer form',
        'Campaign' => clean_utm($body['utm'] ?? []),
    ])
    . "\nAdd to the mailing list platform and keep this email as the consent record.\n";

if (!send_team_mail(new MailMessage('Website: new newsletter subscriber', $text, $email))) {
    fail(502, 'We could not complete your subscription right now. Please try again later.');
}
json_response(200, ['ok' => true]);
