<?php
/** POST /api/contact.php — contact / consultation enquiry. */
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

$body = begin_form_request('contact', 5, 900);
if (is_bot($body)) {
    json_response(200, ['ok' => true, 'data' => ['tier' => 'remote']]);
}

$in = [
    'name' => clean_str($body['name'] ?? '', 100),
    'business' => clean_str($body['business'] ?? '', 150),
    'email' => clean_str($body['email'] ?? '', 254),
    'phone' => clean_str($body['phone'] ?? '', 20),
    'suburb' => clean_str($body['suburb'] ?? '', 80),
    'state' => strtoupper(clean_str($body['state'] ?? '', 3)),
    'meeting' => clean_str($body['meeting'] ?? 'either', 12),
    'message' => clean_str($body['message'] ?? '', 3000, true),
    'marketing' => ($body['marketing'] ?? false) === true,
];

$errors = [];
require_fields($in, ['name' => 'Your name', 'email' => 'Email', 'suburb' => 'Suburb or town', 'state' => 'State', 'message' => 'How can we help?'], $errors);
if ($in['email'] !== '' && !isset($errors['email']) && !valid_email($in['email'])) {
    $errors['email'] = 'Enter a valid email address, like name@example.com.au.';
}
if ($in['phone'] !== '' && !valid_au_phone($in['phone'])) {
    $errors['phone'] = 'Enter a valid Australian phone number, like 0400 000 000.';
}
if (!isset($errors['state']) && !in_array($in['state'], AU_STATES, true)) {
    $errors['state'] = 'Choose a state.';
}
if (!in_array($in['meeting'], ['either', 'in_person', 'video'], true)) {
    $in['meeting'] = 'either';
}
if ($errors) {
    fail(422, 'Please check the highlighted fields.', $errors);
}

$tier = tier_for($in['suburb'], $in['state']);
$text = "New website enquiry — tier: $tier\n\n" . format_fields([
    'Name' => $in['name'],
    'Business' => $in['business'],
    'Email' => $in['email'],
    'Phone' => $in['phone'],
    'Suburb / town' => $in['suburb'],
    'State' => $in['state'],
    'Lead tier' => $tier,
    'Meeting preference' => $in['meeting'],
    'Marketing opt-in' => $in['marketing'],
    'Campaign' => clean_utm($body['utm'] ?? []),
    'Received (UTC)' => gmdate('c'),
]) . "\nMessage:\n" . $in['message'] . "\n";

$subject = sprintf('Website enquiry [%s] — %s', $tier, header_safe($in['business'] !== '' ? $in['business'] : $in['name'], 80));
if (!send_team_mail(new MailMessage($subject, $text, $in['email']))) {
    fail(502, 'We could not send your message right now. Please try again later.');
}
json_response(200, ['ok' => true, 'data' => ['tier' => $tier]]);
