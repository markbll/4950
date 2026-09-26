<?php
/** GET /api/token.php — issues a short-lived signed form token. */
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

require_method('GET');
$token = issue_form_token();
if ($token === null) {
    error_log('[bigcat-api] APP_SECRET missing or shorter than 32 characters.');
    fail(503, 'Forms are temporarily unavailable.');
}
json_response(200, ['ok' => true, 'token' => $token]);
