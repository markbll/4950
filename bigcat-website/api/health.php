<?php
/**
 * GET /api/health.php — configuration health check for deploy/UAT.
 * Reports booleans only: no versions, paths, hostnames or secrets.
 */
declare(strict_types=1);
require __DIR__ . '/lib/bootstrap.php';

require_method('GET');
$checks = [
    'secret_configured' => app_secret() !== null,
    'storage_writable' => storage_dir() !== null,
    'mail_configured' => mail_configured(),
    'origins_configured' => allowed_origins() !== [],
    'curl_available' => function_exists('curl_init'),
    'dom_available' => class_exists('DOMDocument'),
    'localities_loaded' => melbourne_localities() !== [],
];
$ok = !in_array(false, $checks, true);
json_response($ok ? 200 : 503, [
    'ok' => $ok,
    'status' => $ok ? 'ok' : 'degraded',
    'env' => app_env(),
    'checks' => $checks,
    'time' => gmdate('c'),
]);
