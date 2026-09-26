<?php
/**
 * POST /api/checkup.php — Free Local Visibility Check-up.
 * Validates the lead, tags its tier, optionally fetches the public home page
 * (SSRF-protected, see lib/sitecheck.php), emails the lead to the team and
 * returns factual findings. Never returns an invented score.
 */
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';
require __DIR__ . '/lib/sitecheck.php';

const INDUSTRIES = ['trades', 'professional-services', 'health-beauty', 'hospitality', 'retail', 'property', 'other'];
const BUDGETS = ['', 'under-500', '500-1000', '1000-2000', '2000-plus', 'unsure'];

$body = begin_form_request('checkup', 4, 900);
$reference = 'BC-' . gmdate('ymd') . '-' . strtoupper(bin2hex(random_bytes(3)));

if (is_bot($body)) {
    json_response(200, ['ok' => true, 'data' => ['tier' => 'remote', 'reference' => $reference, 'categories' => build_checkup_categories(null, 'Not checked.', [])]]);
}

$in = [
    'businessName' => clean_str($body['businessName'] ?? '', 150),
    'website' => normalise_website(clean_str($body['website'] ?? '', 300)),
    'suburb' => clean_str($body['suburb'] ?? '', 80),
    'state' => strtoupper(clean_str($body['state'] ?? '', 3)),
    'industry' => clean_str($body['industry'] ?? '', 40),
    'mainServiceArea' => clean_str($body['mainServiceArea'] ?? '', 150),
    'primaryService' => clean_str($body['primaryService'] ?? '', 150),
    'budget' => clean_str($body['budget'] ?? '', 20),
    'challenge' => clean_str($body['challenge'] ?? '', 1500, true),
    'contactName' => clean_str($body['contactName'] ?? '', 100),
    'email' => clean_str($body['email'] ?? '', 254),
    'phone' => clean_str($body['phone'] ?? '', 20),
    'consent' => ($body['consent'] ?? false) === true,
    'marketing' => ($body['marketing'] ?? false) === true,
];

$errors = [];
require_fields($in, [
    'businessName' => 'Business name',
    'suburb' => 'Suburb or town',
    'state' => 'State',
    'industry' => 'Industry',
    'mainServiceArea' => 'Main service area',
    'primaryService' => 'Primary service',
    'contactName' => 'Your name',
    'email' => 'Email',
    'phone' => 'Phone',
], $errors);
if (!valid_website($in['website'])) {
    $errors['website'] = 'Enter a website address like example.com.au.';
}
if (!isset($errors['state']) && !in_array($in['state'], AU_STATES, true)) {
    $errors['state'] = 'Choose a state.';
}
if (!isset($errors['industry']) && !in_array($in['industry'], INDUSTRIES, true)) {
    $errors['industry'] = 'Choose an industry.';
}
if (!in_array($in['budget'], BUDGETS, true)) {
    $in['budget'] = '';
}
if ($in['email'] !== '' && !isset($errors['email']) && !valid_email($in['email'])) {
    $errors['email'] = 'Enter a valid email address, like name@example.com.au.';
}
if ($in['phone'] !== '' && !isset($errors['phone']) && !valid_au_phone($in['phone'])) {
    $errors['phone'] = 'Enter a valid Australian phone number, like 0400 000 000.';
}
if (!$in['consent']) {
    $errors['consent'] = 'Please agree so we can send you your check-up.';
}
if ($errors) {
    fail(422, 'Please check the highlighted fields.', $errors);
}

$tier = tier_for($in['suburb'], $in['state']);

// Website checks (optional, server-side, SSRF-protected)
$site = null;
$siteNote = null;
if ($in['website'] === '') {
    $siteNote = 'No website was provided. Reviewed by our team within 1 business day.';
} elseif (env('CHECKUP_FETCH_ENABLED', '1') !== '1') {
    $siteNote = 'Automatic website checks are switched off. Reviewed by our team within 1 business day.';
} else {
    $res = fetch_public_page($in['website']);
    if ($res['ok']) {
        $site = analyse_html($res['html'], $in);
        $site['https'] = $res['https'];
        $site['finalUrl'] = $res['url'];
    } else {
        $siteNote = $res['reason'] . ' Reviewed by our team within 1 business day.';
    }
}
$categories = build_checkup_categories($site, $siteNote, $in);

// Email the lead to the team (plain text; the check-up findings included for context).
$summary = '';
foreach ($categories as $c) {
    $summary .= "- {$c['label']}: {$c['status']}\n";
    foreach ($c['findings'] ?? [] as $fnd) {
        $summary .= "    · {$fnd['result']}: {$fnd['label']}" . (isset($fnd['detail']) ? " ({$fnd['detail']})" : '') . "\n";
    }
}
$text = "New Free Local Visibility Check-up — tier: $tier — ref $reference\n\n" . format_fields([
    'Reference' => $reference,
    'Lead tier' => $tier,
    'Business' => $in['businessName'],
    'Website' => $in['website'],
    'Suburb / town' => $in['suburb'],
    'State' => $in['state'],
    'Industry' => $in['industry'],
    'Main service area' => $in['mainServiceArea'],
    'Primary service' => $in['primaryService'],
    'Budget' => $in['budget'],
    'Contact name' => $in['contactName'],
    'Email' => $in['email'],
    'Phone' => $in['phone'],
    'Contact consent' => $in['consent'],
    'Marketing opt-in' => $in['marketing'],
    'Campaign' => clean_utm($body['utm'] ?? []),
    'Received (UTC)' => gmdate('c'),
]) . "\nBiggest challenge:\n" . ($in['challenge'] !== '' ? $in['challenge'] : '—')
  . "\n\nAutomatic findings (team to complete the review within 1 business day):\n" . $summary;

$subject = sprintf('Check-up [%s] %s — %s', $tier, $reference, header_safe($in['businessName'], 80));
if (!send_team_mail(new MailMessage($subject, $text, $in['email']))) {
    fail(502, 'We could not submit your check-up right now. Please try again later.');
}

json_response(200, ['ok' => true, 'data' => ['tier' => $tier, 'reference' => $reference, 'categories' => $categories]]);
