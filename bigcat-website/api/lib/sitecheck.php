<?php
/**
 * Website local-signal checks for the Free Local Visibility Check-up.
 *
 * SSRF protections:
 *  - http/https only, ports 80/443 only, no credentials in URL
 *  - hostname resolved server-side; EVERY resolved address must be a public,
 *    globally routable IP (private, loopback, link-local, CGNAT, reserved,
 *    multicast and IPv4-mapped private IPv6 are rejected)
 *  - the connection is pinned to the vetted IP (CURLOPT_RESOLVE) so DNS
 *    rebinding cannot swap the target after validation
 *  - redirects are followed manually (max 3) and every hop is re-validated
 *  - connect timeout 4s, total 8s per hop, response capped at 1.5 MB,
 *    only text/html is parsed
 *
 * Results are factual observations only. No scores are produced.
 */
declare(strict_types=1);

const SC_MAX_BYTES = 1_572_864;
const SC_MAX_REDIRECTS = 3;
const SC_USER_AGENT = 'BigCatCheckup/1.0 (+https://bigcatmarketing.com.au/local-visibility-checkup)';

function ip_is_public(string $ip): bool
{
    if (filter_var($ip, FILTER_VALIDATE_IP) === false) {
        return false;
    }
    // IPv4-mapped / compatible IPv6 — check the embedded IPv4.
    if (preg_match('/^::(ffff:)?(\d+\.\d+\.\d+\.\d+)$/i', $ip, $m)) {
        return ip_is_public($m[2]);
    }
    $flags = FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE;
    if (defined('FILTER_FLAG_GLOBAL_RANGE')) {
        $flags |= FILTER_FLAG_GLOBAL_RANGE;
    }
    if (filter_var($ip, FILTER_VALIDATE_IP, $flags) === false) {
        return false;
    }
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        $long = ip2long($ip);
        $blocked = [
            ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8], ['169.254.0.0', 16],
            ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24], ['192.88.99.0', 24], ['192.168.0.0', 16],
            ['198.18.0.0', 15], ['198.51.100.0', 24], ['203.0.113.0', 24], ['224.0.0.0', 4], ['240.0.0.0', 4],
        ];
        foreach ($blocked as [$net, $bits]) {
            $mask = -1 << (32 - $bits);
            if (($long & $mask) === (ip2long($net) & $mask)) {
                return false;
            }
        }
        return true;
    }
    // IPv6: block loopback, unspecified, ULA fc00::/7, link-local fe80::/10, multicast ff00::/8, documentation 2001:db8::/32, 64:ff9b::/96 NAT64
    $bin = inet_pton($ip);
    if ($bin === false) {
        return false;
    }
    $hex = bin2hex($bin);
    if ($hex === str_repeat('0', 31) . '1' || $hex === str_repeat('0', 32)) {
        return false;
    }
    $first = hexdec(substr($hex, 0, 2));
    if (($first & 0xFE) === 0xFC || $first === 0xFF) {
        return false;
    }
    if (substr($hex, 0, 3) === 'fe8' || substr($hex, 0, 3) === 'fe9' || substr($hex, 0, 3) === 'fea' || substr($hex, 0, 3) === 'feb') {
        return false;
    }
    if (str_starts_with($hex, '20010db8') || str_starts_with($hex, '0064ff9b')) {
        return false;
    }
    return true;
}

/** @return string[] resolved IPs, or [] if resolution fails */
function resolve_host(string $host): array
{
    if (filter_var($host, FILTER_VALIDATE_IP)) {
        return [$host];
    }
    $ips = [];
    $a = @dns_get_record($host, DNS_A) ?: [];
    foreach ($a as $r) {
        if (!empty($r['ip'])) {
            $ips[] = $r['ip'];
        }
    }
    $aaaa = @dns_get_record($host, DNS_AAAA) ?: [];
    foreach ($aaaa as $r) {
        if (!empty($r['ipv6'])) {
            $ips[] = $r['ipv6'];
        }
    }
    if (!$ips) {
        $fallback = @gethostbynamel($host) ?: [];
        $ips = $fallback;
    }
    return array_values(array_unique($ips));
}

/**
 * @return array{ok:bool, reason?:string, host?:string, ip?:string, port?:int, scheme?:string}
 */
function vet_url(string $url): array
{
    $p = parse_url($url);
    $scheme = strtolower($p['scheme'] ?? '');
    $host = strtolower(rtrim($p['host'] ?? '', '.'));
    if (!in_array($scheme, ['http', 'https'], true) || $host === '' || isset($p['user']) || isset($p['pass'])) {
        return ['ok' => false, 'reason' => 'That website address is not supported.'];
    }
    $port = $p['port'] ?? ($scheme === 'https' ? 443 : 80);
    if (!in_array($port, [80, 443], true)) {
        return ['ok' => false, 'reason' => 'Only standard web ports can be checked.'];
    }
    if ($host === 'localhost' || str_ends_with($host, '.localhost') || str_ends_with($host, '.local') || str_ends_with($host, '.internal')) {
        return ['ok' => false, 'reason' => 'That website address is not public.'];
    }
    $host = trim($host, '[]');
    $ips = resolve_host($host);
    if (!$ips) {
        return ['ok' => false, 'reason' => 'We could not find that website (DNS lookup failed).'];
    }
    foreach ($ips as $ip) {
        if (!ip_is_public($ip)) {
            return ['ok' => false, 'reason' => 'That website address is not public.'];
        }
    }
    $v4 = array_values(array_filter($ips, static fn($i) => filter_var($i, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)));
    return ['ok' => true, 'host' => $host, 'ip' => $v4[0] ?? $ips[0], 'port' => $port, 'scheme' => $scheme];
}

/**
 * @return array{ok:bool, reason?:string, url?:string, status?:int, html?:string, https?:bool}
 */
function fetch_public_page(string $url): array
{
    if (!function_exists('curl_init')) {
        return ['ok' => false, 'reason' => 'Automatic checks are unavailable.'];
    }
    for ($hop = 0; $hop <= SC_MAX_REDIRECTS; $hop++) {
        $v = vet_url($url);
        if (!$v['ok']) {
            return ['ok' => false, 'reason' => $v['reason']];
        }
        $ipForResolve = str_contains($v['ip'], ':') ? '[' . $v['ip'] . ']' : $v['ip'];
        $body = '';
        $headers = [];
        $tooBig = false;
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RESOLVE => [$v['host'] . ':' . $v['port'] . ':' . $ipForResolve],
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
            CURLOPT_CONNECTTIMEOUT => 4,
            CURLOPT_TIMEOUT => 8,
            CURLOPT_USERAGENT => SC_USER_AGENT,
            CURLOPT_HTTPHEADER => ['Accept: text/html,application/xhtml+xml;q=0.9', 'Accept-Language: en-AU,en;q=0.8'],
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_ENCODING => '',
            CURLOPT_NOPROXY => '*',
            CURLOPT_HEADERFUNCTION => static function ($ch, string $line) use (&$headers): int {
                $parts = explode(':', $line, 2);
                if (count($parts) === 2) {
                    $headers[strtolower(trim($parts[0]))] = trim($parts[1]);
                }
                return strlen($line);
            },
            CURLOPT_WRITEFUNCTION => static function ($ch, string $chunk) use (&$body, &$tooBig): int {
                if (strlen($body) + strlen($chunk) > SC_MAX_BYTES) {
                    $tooBig = true;
                    return 0; // abort transfer
                }
                $body .= $chunk;
                return strlen($chunk);
            },
        ]);
        curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err = curl_errno($ch);
        curl_close($ch);

        if ($tooBig) {
            return ['ok' => false, 'reason' => 'The home page was too large to check automatically.'];
        }
        if ($err !== 0 && $status === 0) {
            return ['ok' => false, 'reason' => $err === CURLE_OPERATION_TIMEDOUT ? 'The website took too long to respond.' : 'We could not connect to the website.'];
        }
        if ($status >= 300 && $status < 400 && !empty($headers['location'])) {
            $url = resolve_redirect($url, $headers['location']);
            if ($url === null) {
                return ['ok' => false, 'reason' => 'The website redirected somewhere we could not follow.'];
            }
            continue;
        }
        if ($status < 200 || $status >= 300) {
            return ['ok' => false, 'reason' => "The website returned an error (HTTP $status)."];
        }
        $ctype = strtolower($headers['content-type'] ?? '');
        if ($ctype !== '' && !str_contains($ctype, 'text/html') && !str_contains($ctype, 'application/xhtml')) {
            return ['ok' => false, 'reason' => 'The address did not return a web page.'];
        }
        return ['ok' => true, 'url' => $url, 'status' => $status, 'html' => $body, 'https' => str_starts_with(strtolower($url), 'https://')];
    }
    return ['ok' => false, 'reason' => 'The website redirected too many times.'];
}

function resolve_redirect(string $base, string $location): ?string
{
    $location = trim($location);
    if (preg_match('#^https?://#i', $location)) {
        return $location;
    }
    $b = parse_url($base);
    if (!$b || empty($b['scheme']) || empty($b['host'])) {
        return null;
    }
    $origin = $b['scheme'] . '://' . $b['host'] . (isset($b['port']) ? ':' . $b['port'] : '');
    if (str_starts_with($location, '//')) {
        return $b['scheme'] . ':' . $location;
    }
    if (str_starts_with($location, '/')) {
        return $origin . $location;
    }
    $dir = isset($b['path']) ? preg_replace('#/[^/]*$#', '/', $b['path']) : '/';
    return $origin . $dir . $location;
}

/**
 * Extract local signals from HTML.
 * @return array<string,mixed>
 */
function analyse_html(string $html, array $ctx): array
{
    $prev = libxml_use_internal_errors(true);
    $doc = new DOMDocument();
    $doc->loadHTML('<?xml encoding="UTF-8">' . $html, LIBXML_NONET | LIBXML_NOERROR | LIBXML_NOWARNING | LIBXML_COMPACT);
    libxml_clear_errors();
    libxml_use_internal_errors($prev);
    $xp = new DOMXPath($doc);

    $first = static function (string $q) use ($xp): string {
        $n = $xp->query($q);
        return ($n && $n->length) ? trim(preg_replace('/\s+/', ' ', (string) $n->item(0)->textContent) ?? '') : '';
    };
    $attr = static function (string $q) use ($xp): string {
        $n = $xp->query($q);
        return ($n && $n->length) ? trim((string) $n->item(0)->nodeValue) : '';
    };

    $title = $first('//title');
    $metaDesc = $attr('//meta[translate(@name,"DESCRIPTION","description")="description"]/@content');
    $viewport = $attr('//meta[translate(@name,"VIEWPORT","viewport")="viewport"]/@content');
    $h1s = [];
    foreach ($xp->query('//h1') ?: [] as $h) {
        $t = trim(preg_replace('/\s+/', ' ', $h->textContent) ?? '');
        if ($t !== '') {
            $h1s[] = mb_substr($t, 0, 120);
        }
    }
    $telLinks = [];
    $social = [];
    $mapsLink = false;
    foreach ($xp->query('//a[@href]') ?: [] as $a) {
        $href = strtolower(trim($a->getAttribute('href')));
        if (str_starts_with($href, 'tel:')) {
            $telLinks[] = preg_replace('/[^\d+]/', '', substr($href, 4));
        }
        foreach (['facebook.com' => 'Facebook', 'instagram.com' => 'Instagram', 'linkedin.com' => 'LinkedIn', 'tiktok.com' => 'TikTok', 'youtube.com' => 'YouTube', 'x.com' => 'X', 'twitter.com' => 'X'] as $domain => $name) {
            if (preg_match('#^https?://([a-z0-9-]+\.)*' . preg_quote($domain, '#') . '/#', $href)) {
                $social[$name] = true;
            }
        }
        if (preg_match('#(google\.[a-z.]+/maps|maps\.google\.|goo\.gl/maps|maps\.app\.goo\.gl|g\.page)#', $href)) {
            $mapsLink = true;
        }
    }
    foreach ($xp->query('//iframe[@src]') ?: [] as $f) {
        if (preg_match('#google\.[a-z.]+/maps#', strtolower($f->getAttribute('src')))) {
            $mapsLink = true;
        }
    }

    // Structured data
    $types = [];
    $hasFaqSchema = false;
    foreach ($xp->query('//script[@type="application/ld+json"]') ?: [] as $s) {
        $json = json_decode(trim($s->textContent), true);
        if (!is_array($json)) {
            continue;
        }
        array_walk_recursive($json, static function ($v, $k) use (&$types) {
            if ($k === '@type' && is_string($v)) {
                $types[] = $v;
            }
        });
    }
    $types = array_values(array_unique($types));
    $hasFaqSchema = in_array('FAQPage', $types, true);
    $localTypes = array_values(array_filter($types, static fn($t) => (bool) preg_match('/(LocalBusiness|ProfessionalService|Store|Restaurant|Cafe|Dentist|Physician|Plumber|Electrician|Contractor|HomeAndConstructionBusiness|AutoRepair|BeautySalon|HairSalon|HealthAndBeautyBusiness|LegalService|Attorney|AccountingService|FinancialService|RealEstateAgent|FoodEstablishment|MedicalBusiness|SportsActivityLocation|LodgingBusiness)/', $t)));

    // Visible text (strip script/style)
    foreach (['script', 'style', 'noscript', 'template'] as $tag) {
        foreach (iterator_to_array($xp->query("//$tag") ?: []) as $n) {
            $n->parentNode?->removeChild($n);
        }
    }
    $text = mb_strtolower(preg_replace('/\s+/', ' ', (string) ($doc->documentElement?->textContent ?? '')) ?? '');

    $phonesInText = [];
    if (preg_match_all('/(?:\+?61[\s-]?|0)[2-478](?:[\s-]?\d){8}|1[38]00(?:[\s-]?\d){6}|\b13(?:[\s-]?\d){4}\b/', $text, $m)) {
        $phonesInText = array_map(static fn($p) => preg_replace('/\D/', '', $p), $m[0]);
    }
    $norm = static function (string $p): string {
        $d = preg_replace('/\D/', '', $p) ?? '';
        return preg_replace('/^61/', '0', $d) ?? $d;
    };
    $allPhones = array_unique(array_map($norm, array_merge($telLinks, $phonesInText)));
    $userPhone = $norm((string) ($ctx['phone'] ?? ''));

    $contains = static function (string $needle) use ($text): bool {
        $n = mb_strtolower(trim($needle));
        return $n !== '' && mb_strlen($n) >= 3 && str_contains($text, $n);
    };
    $businessName = (string) ($ctx['businessName'] ?? '');

    return [
        'title' => mb_substr($title, 0, 160),
        'metaDescription' => $metaDesc !== '',
        'viewport' => $viewport !== '' && str_contains(strtolower($viewport), 'width=device-width'),
        'h1' => $h1s,
        'telLink' => count($telLinks) > 0,
        'phoneFound' => count($allPhones) > 0,
        'phoneMatches' => $userPhone !== '' && in_array($userPhone, $allPhones, true),
        'schemaTypes' => array_slice($types, 0, 15),
        'localBusinessSchema' => $localTypes,
        'faqSchema' => $hasFaqSchema,
        'faqContent' => $hasFaqSchema || str_contains($text, 'frequently asked') || str_contains($text, 'faq'),
        'social' => array_keys($social),
        'mapsLink' => $mapsLink,
        'mentionsSuburb' => $contains((string) ($ctx['suburb'] ?? '')),
        'mentionsServiceArea' => $contains((string) ($ctx['mainServiceArea'] ?? '')),
        'mentionsService' => $contains((string) ($ctx['primaryService'] ?? '')),
        'mentionsBusinessName' => $contains($businessName),
        'titleMentionsLocation' => $contains((string) ($ctx['suburb'] ?? '')) && str_contains(mb_strtolower($title), mb_strtolower((string) ($ctx['suburb'] ?? ''))),
        'wordCount' => str_word_count($text),
    ];
}

/**
 * Build the eight result categories. Anything not measured is explicitly
 * "team_review" or "not_checked" — never an invented score.
 * @return array<int,array<string,mixed>>
 */
function build_checkup_categories(?array $site, ?string $siteNote, array $ctx): array
{
    $f = static fn(string $label, ?bool $ok, ?string $detail = null) => array_filter([
        'label' => $label,
        'result' => $ok === null ? 'info' : ($ok ? 'found' : 'missing'),
        'detail' => $detail,
    ], static fn($v) => $v !== null);

    $review = 'Reviewed by our team within 1 business day.';
    $service = (string) ($ctx['primaryService'] ?? 'your main service');
    $suburb = (string) ($ctx['suburb'] ?? 'your area');
    $cats = [];

    $cats[] = ['key' => 'gbp', 'label' => 'Google Business Profile', 'status' => 'team_review',
        'summary' => "$review We will check your categories, services, service areas, hours, photos, posts and Q&A."];
    $cats[] = ['key' => 'map_pack', 'label' => 'Map Pack presence', 'status' => 'team_review',
        'summary' => "$review We will look at where you appear in Google Maps for “{$service}” searches around {$suburb}. We do not estimate this automatically."];
    $cats[] = ['key' => 'reviews', 'label' => 'Reviews', 'status' => 'team_review',
        'summary' => "$review We will look at your review count, recency and responses on Google."];

    if ($site === null) {
        $why = $siteNote ?? 'No website was provided.';
        foreach ([['nap', 'NAP consistency'], ['website', 'Website local signals'], ['local_content', 'Local content'], ['social', 'Social'], ['ai_search', 'AI-search readiness']] as [$k, $l]) {
            $cats[] = ['key' => $k, 'label' => $l, 'status' => $k === 'nap' ? 'team_review' : 'not_checked',
                'summary' => ($k === 'nap' ? "$review " : '') . "Website not checked automatically: $why"];
        }
        return $cats;
    }

    $cats[] = ['key' => 'nap', 'label' => 'NAP consistency', 'status' => 'checked',
        'summary' => 'We checked your home page for your business name and phone number. Consistency across directories (citations) is reviewed by our team within 1 business day.',
        'findings' => [
            $f('Business name on home page', $site['mentionsBusinessName']),
            $f('Phone number on home page', $site['phoneFound']),
            $f('Matches the phone number you gave us', ($ctx['phone'] ?? '') !== '' ? $site['phoneMatches'] : null),
        ]];

    $cats[] = ['key' => 'website', 'label' => 'Website local signals', 'status' => 'checked',
        'summary' => 'What we found on your public home page.',
        'findings' => array_values(array_filter([
            $f('Secure connection (HTTPS)', $site['https']),
            $f('Page title', $site['title'] !== '', $site['title'] !== '' ? '“' . $site['title'] . '”' : null),
            $f('Meta description', $site['metaDescription']),
            $f('Main heading (H1)', count($site['h1']) > 0, $site['h1'] ? '“' . $site['h1'][0] . '”' : null),
            $f('Mobile viewport set', $site['viewport']),
            $f('Click-to-call phone link', $site['telLink']),
            $f('LocalBusiness structured data', count($site['localBusinessSchema']) > 0, $site['localBusinessSchema'] ? implode(', ', $site['localBusinessSchema']) : null),
            $f('Link to Google Maps / directions', $site['mapsLink']),
        ]))];

    $cats[] = ['key' => 'local_content', 'label' => 'Local content', 'status' => 'checked',
        'summary' => 'Whether your home page mentions where you work and what you do. Other pages are reviewed by our team.',
        'findings' => [
            $f("Mentions “{$suburb}”", $site['mentionsSuburb']),
            $f('Mentions your main service area', ($ctx['mainServiceArea'] ?? '') !== '' ? $site['mentionsServiceArea'] : null),
            $f("Mentions “{$service}”", $site['mentionsService']),
            $f('Location in page title', $site['titleMentionsLocation']),
        ]];

    $cats[] = ['key' => 'social', 'label' => 'Social', 'status' => 'checked',
        'summary' => 'Social profiles linked from your home page. How active they are is reviewed by our team.',
        'findings' => [
            $f('Social profile links', count($site['social']) > 0, $site['social'] ? implode(', ', $site['social']) : null),
        ]];

    $cats[] = ['key' => 'ai_search', 'label' => 'AI-search readiness', 'status' => 'checked',
        'summary' => 'Signals that help search engines and AI assistants understand your business. This is a checklist, not a score.',
        'findings' => [
            $f('Structured data present', count($site['schemaTypes']) > 0, $site['schemaTypes'] ? implode(', ', array_slice($site['schemaTypes'], 0, 6)) : null),
            $f('FAQ content or FAQ schema', $site['faqContent']),
            $f('Clear page description (meta description)', $site['metaDescription']),
            $f('Clear main heading', count($site['h1']) === 1, count($site['h1']) > 1 ? count($site['h1']) . ' H1 headings found' : null),
        ]];

    return $cats;
}
