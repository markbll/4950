<?php
/**
 * Dependency-free PHP test runner: `php api/tests/run.php` (also run by `npm test`).
 */
declare(strict_types=1);

$storage = sys_get_temp_dir() . '/bigcat-test-' . bin2hex(random_bytes(4));
putenv('APP_SECRET=' . str_repeat('t', 40));
putenv('STORAGE_DIR=' . $storage);
putenv('APP_ENV=development');
$_SERVER['DOCUMENT_ROOT'] = __DIR__;

require __DIR__ . '/../lib/config.php';
require __DIR__ . '/../lib/http.php';
require __DIR__ . '/../lib/validate.php';
require __DIR__ . '/../lib/ratelimit.php';
require __DIR__ . '/../lib/token.php';
require __DIR__ . '/../lib/mailer.php';
require __DIR__ . '/../lib/tier.php';
require __DIR__ . '/../lib/sitecheck.php';

$passed = 0;
$failed = [];
function check(string $name, bool $cond): void
{
    global $passed, $failed;
    if ($cond) {
        $passed++;
    } else {
        $failed[] = $name;
    }
}

// --- tier tagging (shared fixtures with the TypeScript tests)
$fx = json_decode((string) file_get_contents(__DIR__ . '/../../shared/tier-fixtures.json'), true);
foreach ($fx['cases'] as $c) {
    check("tier {$c['suburb']}/{$c['state']} => {$c['tier']}", tier_for($c['suburb'], $c['state']) === $c['tier']);
}
check('deployed localities copy matches shared list',
    file_get_contents(__DIR__ . '/../lib/greater-melbourne-localities.json') === file_get_contents(__DIR__ . '/../../shared/greater-melbourne-localities.json'));

// --- validation
check('valid mobile', valid_au_phone('0412 345 678'));
check('valid landline', valid_au_phone('(03) 9123 4567'));
check('valid +61', valid_au_phone('+61 3 9123 4567'));
check('valid 1300', valid_au_phone('1300 123 456'));
check('invalid phone', !valid_au_phone('12345'));
check('invalid phone letters', !valid_au_phone('04123abc78'));
check('valid email', valid_email('owner@example.com.au'));
check('email header injection rejected', !valid_email("a@b.com\r\nBcc: x@y.com"));
check('invalid email', !valid_email('not-an-email'));
check('website ok', valid_website(normalise_website('example.com.au')));
check('website javascript rejected', !valid_website('javascript:alert(1)'));
check('website creds rejected', !valid_website('https://user:pass@example.com'));
check('website ftp rejected', !valid_website('ftp://example.com'));
check('clean_str strips control chars', clean_str("hi\x00\x07there", 50) === 'hi there');
check('clean_str caps length', mb_strlen(clean_str(str_repeat('a', 500), 100)) === 100);
check('clean_str multiline keeps newlines', clean_str("a\r\nb", 50, true) === "a\nb");
check('header_safe strips CRLF', !str_contains(header_safe("Subject\r\nBcc: evil@x.com"), "\n"));
check('utm cleaned', clean_utm(['utm_source' => 'goo<gle>', 'evil' => 'x']) === ['utm_source' => 'google']);

// --- SSRF guards
foreach (['127.0.0.1', '10.1.2.3', '172.16.5.4', '192.168.1.1', '169.254.169.254', '100.64.1.1', '0.0.0.0', '::1', 'fe80::1', 'fd00::1', '::ffff:127.0.0.1', '::ffff:10.0.0.1', '224.0.0.1', '198.18.0.1'] as $ip) {
    check("ip $ip is not public", !ip_is_public($ip));
}
foreach (['8.8.8.8', '1.1.1.1', '2606:4700:4700::1111'] as $ip) {
    check("ip $ip is public", ip_is_public($ip));
}
foreach (['http://localhost/', 'http://127.0.0.1/', 'http://169.254.169.254/latest/meta-data/', 'http://[::1]/', 'http://10.0.0.1/', 'https://example.com:8443/', 'file:///etc/passwd', 'gopher://example.com/', 'http://user:pw@example.com/', 'http://printer.local/'] as $u) {
    check("vet_url rejects $u", vet_url($u)['ok'] === false);
}
check('redirect relative', resolve_redirect('https://a.com/x/y', '/z') === 'https://a.com/z');
check('redirect protocol-relative', resolve_redirect('https://a.com/x', '//b.com/') === 'https://b.com/');

// --- tokens
$now = time();
$t = issue_form_token($now - 10);
check('token verifies', verify_form_token((string) $t, $now));
check('token too fresh rejected', !verify_form_token((string) issue_form_token($now), $now));
check('token expired rejected', !verify_form_token((string) issue_form_token($now - 8000), $now));
check('token tamper rejected', !verify_form_token(substr((string) $t, 0, -1) . (substr((string) $t, -1) === 'a' ? 'b' : 'a'), $now));
check('token garbage rejected', !verify_form_token('abc', $now));

// --- rate limit
for ($i = 0; $i < 3; $i++) {
    rate_limit_hit('test', '203.0.113.9', 3, 60);
}
check('rate limit blocks 4th', rate_limit_hit('test', '203.0.113.9', 3, 60) === false);
check('rate limit separate ip ok', rate_limit_hit('test', '203.0.113.10', 3, 60) === true);
$files = glob($storage . '/ratelimit/*.json') ?: [];
check('rate limit stores no raw IP', !str_contains(implode('', array_map('file_get_contents', $files)) . implode('', $files), '203.0.113'));

// --- HTML analysis + categories
$html = <<<'HTML'
<!doctype html><html><head><title>Acme Plumbing Coburg | Emergency Plumber</title>
<meta name="description" content="Plumber in Coburg"><meta name="viewport" content="width=device-width, initial-scale=1">
<script type="application/ld+json">{"@context":"https://schema.org","@type":"Plumber","name":"Acme Plumbing"}</script>
</head><body><h1>Emergency plumber in Coburg</h1><p>Acme Plumbing serves Coburg and the northern suburbs.</p>
<a href="tel:+61391234567">03 9123 4567</a><a href="https://www.facebook.com/acme/">Facebook</a>
<a href="https://maps.app.goo.gl/abc">Directions</a><script>var x = "Brunswick";</script></body></html>
HTML;
$ctx = ['suburb' => 'Coburg', 'mainServiceArea' => 'northern suburbs', 'primaryService' => 'emergency plumber', 'businessName' => 'Acme Plumbing', 'phone' => '03 9123 4567'];
$a = analyse_html($html, $ctx);
check('analyse title', str_contains($a['title'], 'Acme'));
check('analyse viewport', $a['viewport'] === true);
check('analyse h1', count($a['h1']) === 1);
check('analyse tel link', $a['telLink'] === true);
check('analyse phone matches', $a['phoneMatches'] === true);
check('analyse local schema', in_array('Plumber', $a['localBusinessSchema'], true));
check('analyse social', $a['social'] === ['Facebook']);
check('analyse maps link', $a['mapsLink'] === true);
check('analyse suburb', $a['mentionsSuburb'] === true);
check('analyse service area', $a['mentionsServiceArea'] === true);
check('analyse ignores script text', analyse_html($html, ['suburb' => 'Brunswick'])['mentionsSuburb'] === false);
$a['https'] = true;
$cats = build_checkup_categories($a, null, $ctx);
check('8 categories', count($cats) === 8);
$json = json_encode($cats);
check('no scores in output', !preg_match('/"score"|\d+\s*\/\s*100|\d+%/', (string) $json));
$none = build_checkup_categories(null, 'No website was provided.', $ctx);
check('no-site categories never "checked"', !in_array('checked', array_column($none, 'status'), true));
check('gbp always team review', $none[0]['status'] === 'team_review' && $cats[0]['status'] === 'team_review');

// --- mail config safety
putenv('MAIL_TRANSPORT=log');
putenv('MAIL_TO=team@example.com');
putenv('MAIL_FROM=web@example.com');
check('log transport allowed in development', mail_configured());
putenv('APP_ENV=production');
check('log transport refused in production', !mail_configured());
putenv('APP_ENV=development');
check('log mail written', send_team_mail(new MailMessage("Subj\r\nBcc: evil@x.com", 'Body', "reply@example.com\r\nBcc: x@y.com")));
$eml = (string) file_get_contents((glob($storage . '/mail-log/*.eml') ?: [''])[0]);
check('no header injection in mail', !preg_match('/^Bcc:/mi', $eml));
check('invalid reply-to dropped', !str_contains($eml, 'Reply-To'));

// cleanup
foreach (array_merge(glob($storage . '/*/*') ?: [], glob($storage . '/*') ?: []) as $f) {
    is_dir($f) ? @rmdir($f) : @unlink($f);
}
@rmdir($storage);

$total = $passed + count($failed);
if ($failed) {
    fwrite(STDERR, "PHP tests: " . count($failed) . " of $total FAILED\n");
    foreach ($failed as $f) {
        fwrite(STDERR, "  ✖ $f\n");
    }
    exit(1);
}
echo "PHP tests: all $total passed\n";
