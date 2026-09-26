<?php
/**
 * Development router for `php -S` (npm run dev:api). Serves ONLY public
 * endpoint scripts in api/ — never lib/ or tests/. Not used in production.
 */
declare(strict_types=1);
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
if (!preg_match('#^/api/([a-z-]+)\.php$#', $path, $m) || !is_file(__DIR__ . '/' . $m[1] . '.php') || $m[1] === 'dev-router') {
    http_response_code(404);
    header('Content-Type: application/json');
    echo '{"ok":false,"message":"Not found"}';
    return true;
}
chdir(__DIR__);
require __DIR__ . '/' . $m[1] . '.php';
return true;
