<?php
/**
 * Stateless signed form tokens: "<issuedAt>.<nonce>.<hmac>".
 * - Proves the request came from a page that loaded our token endpoint
 * - Enforces a minimum fill time (bots submit instantly) and a maximum age
 */
declare(strict_types=1);

const TOKEN_MIN_AGE = 2;      // seconds
const TOKEN_MAX_AGE = 7200;   // 2 hours

function issue_form_token(?int $now = null): ?string
{
    $secret = app_secret();
    if ($secret === null) {
        return null;
    }
    $ts = (string) ($now ?? time());
    $nonce = bin2hex(random_bytes(8));
    $sig = hash_hmac('sha256', "$ts.$nonce", $secret);
    return "$ts.$nonce.$sig";
}

function verify_form_token(string $token, ?int $now = null): bool
{
    $secret = app_secret();
    if ($secret === null || !preg_match('/^(\d{10})\.([a-f0-9]{16})\.([a-f0-9]{64})$/', $token, $m)) {
        return false;
    }
    $expected = hash_hmac('sha256', "{$m[1]}.{$m[2]}", $secret);
    if (!hash_equals($expected, $m[3])) {
        return false;
    }
    $age = ($now ?? time()) - (int) $m[1];
    return $age >= TOKEN_MIN_AGE && $age <= TOKEN_MAX_AGE;
}
