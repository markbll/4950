<?php
declare(strict_types=1);

const AU_STATES = ['VIC', 'NSW', 'QLD', 'SA', 'WA', 'TAS', 'ACT', 'NT'];

/** Trim, strip control characters (keeps newlines only when $multiline) and cap length. */
function clean_str(mixed $v, int $max, bool $multiline = false): string
{
    if (!is_string($v) && !is_int($v) && !is_float($v)) {
        return '';
    }
    $s = (string) $v;
    if (!mb_check_encoding($s, 'UTF-8')) {
        $s = mb_convert_encoding($s, 'UTF-8', 'UTF-8');
    }
    $s = $multiline
        ? preg_replace('/[^\P{C}\n\t]/u', '', str_replace("\r\n", "\n", $s))
        : preg_replace('/\p{C}+/u', ' ', $s);
    $s = trim((string) $s);
    return mb_substr($s, 0, $max);
}

function valid_email(string $email): bool
{
    return strlen($email) <= 254
        && filter_var($email, FILTER_VALIDATE_EMAIL) !== false
        && !preg_match('/[\r\n]/', $email);
}

function valid_au_phone(string $phone): bool
{
    $c = preg_replace('/[()\s.-]/', '', $phone) ?? '';
    return (bool) preg_match('/^(?:\+?61|0)[2-478]\d{8}$|^1[38]00\d{6}$|^13\d{4}$/', $c);
}

function normalise_website(string $url): string
{
    $url = trim($url);
    if ($url === '') {
        return '';
    }
    if (!preg_match('#^https?://#i', $url)) {
        $url = 'https://' . $url;
    }
    return $url;
}

function valid_website(string $url): bool
{
    if ($url === '') {
        return true;
    }
    if (strlen($url) > 300 || filter_var($url, FILTER_VALIDATE_URL) === false) {
        return false;
    }
    $p = parse_url($url);
    return in_array(strtolower($p['scheme'] ?? ''), ['http', 'https'], true)
        && !empty($p['host'])
        && str_contains($p['host'], '.')
        && !isset($p['user'])
        && !isset($p['pass']);
}

/** Header-safe single line (for subjects/names). */
function header_safe(string $s, int $max = 120): string
{
    return mb_substr(trim(preg_replace('/[\r\n\t\x00-\x1F\x7F]+/', ' ', $s) ?? ''), 0, $max);
}

/**
 * @param array<string,mixed> $body
 * @param array<string,string> $fields field => label
 * @param array<string,string> $errors
 */
function require_fields(array $body, array $fields, array &$errors): void
{
    foreach ($fields as $f => $label) {
        $v = $body[$f] ?? '';
        if ((is_string($v) && trim($v) === '') || $v === null || $v === false) {
            $errors[$f] = "$label is required.";
        }
    }
}

/** @param array<string,mixed> $utm */
function clean_utm(mixed $utm): array
{
    $out = [];
    if (!is_array($utm)) {
        return $out;
    }
    foreach (['utm_source', 'utm_medium', 'utm_campaign'] as $k) {
        if (isset($utm[$k]) && is_string($utm[$k])) {
            $out[$k] = preg_replace('/[^\w.\- ]/', '', mb_substr($utm[$k], 0, 60)) ?? '';
        }
    }
    return array_filter($out);
}
