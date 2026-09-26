<?php
declare(strict_types=1);

const MAX_BODY_BYTES = 32768;

function send_security_headers(): void
{
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");
    header('Cross-Origin-Resource-Policy: same-origin');
    header('Cache-Control: no-store, max-age=0');
    header('X-Robots-Tag: noindex, nofollow');
}

/** @param array<string,mixed> $data */
function json_response(int $status, array $data): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(int $status, string $message, array $errors = []): never
{
    $body = ['ok' => false, 'message' => $message];
    if ($errors) {
        $body['errors'] = $errors;
    }
    json_response($status, $body);
}

function require_method(string $method): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== $method) {
        header('Allow: ' . $method);
        fail(405, 'Method not allowed.');
    }
}

/**
 * CSRF defence for a same-origin JSON API:
 *  1. Content-Type must be application/json (cannot be sent cross-site without a CORS preflight, which we never grant)
 *  2. Custom X-Requested-With header required (same reason)
 *  3. Origin (or Referer) must be one of ALLOWED_ORIGINS
 *  4. A signed, time-limited form token (see token.php)
 */
function require_same_origin_json(): void
{
    $ctype = strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0]));
    if ($ctype !== 'application/json') {
        fail(415, 'Unsupported content type.');
    }
    if (($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') !== 'fetch') {
        fail(403, 'Request rejected.');
    }
    $allowed = allowed_origins();
    if (!$allowed) {
        error_log('[bigcat-api] ALLOWED_ORIGINS is not configured.');
        fail(503, 'Forms are temporarily unavailable.');
    }
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin === '' && !empty($_SERVER['HTTP_REFERER'])) {
        $p = parse_url((string) $_SERVER['HTTP_REFERER']);
        if (!empty($p['scheme']) && !empty($p['host'])) {
            $origin = $p['scheme'] . '://' . $p['host'] . (isset($p['port']) ? ':' . $p['port'] : '');
        }
    }
    if (!in_array(rtrim($origin, '/'), $allowed, true)) {
        fail(403, 'Request rejected.');
    }
}

/** @return array<string,mixed> */
function read_json_body(): array
{
    $len = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($len > MAX_BODY_BYTES) {
        fail(413, 'Request too large.');
    }
    $raw = file_get_contents('php://input', false, null, 0, MAX_BODY_BYTES + 1);
    if ($raw === false || strlen($raw) > MAX_BODY_BYTES) {
        fail(413, 'Request too large.');
    }
    try {
        $data = json_decode($raw, true, 8, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        fail(400, 'Invalid request.');
    }
    if (!is_array($data)) {
        fail(400, 'Invalid request.');
    }
    return $data;
}

function client_ip(): string
{
    // Only trust a proxy header if explicitly configured (e.g. behind Cloudflare: TRUSTED_PROXY_HEADER=HTTP_CF_CONNECTING_IP).
    $hdr = env('TRUSTED_PROXY_HEADER');
    if ($hdr !== null && preg_match('/^HTTP_[A-Z0-9_]+$/', $hdr) && !empty($_SERVER[$hdr])) {
        $ip = trim(explode(',', (string) $_SERVER[$hdr])[0]);
        if (filter_var($ip, FILTER_VALIDATE_IP)) {
            return $ip;
        }
    }
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
}

/** Standard pre-flight for form endpoints. Returns the decoded body. */
function begin_form_request(string $bucket, int $limit, int $windowSeconds): array
{
    require_method('POST');
    require_same_origin_json();
    if (app_secret() === null || storage_dir() === null) {
        error_log('[bigcat-api] APP_SECRET or STORAGE_DIR not configured.');
        fail(503, 'Forms are temporarily unavailable.');
    }
    // RATE_LIMIT_SCALE (default 1) exists only so automated UAT can run many submissions; never raise it in production.
    $scale = app_env() === 'production' ? 1 : max(1, min(20, (int) env('RATE_LIMIT_SCALE', '1')));
    if (!rate_limit_hit($bucket, client_ip(), $limit * $scale, $windowSeconds)) {
        header('Retry-After: ' . $windowSeconds);
        fail(429, 'Too many attempts. Please wait a few minutes and try again.');
    }
    if (!verify_form_token((string) ($_SERVER['HTTP_X_FORM_TOKEN'] ?? ''))) {
        fail(403, 'Your session expired. Please refresh the page and try again.');
    }
    return read_json_body();
}

/** True if the honeypot was filled (bot). */
function is_bot(array $body): bool
{
    return isset($body['company_fax']) && trim((string) $body['company_fax']) !== '';
}
