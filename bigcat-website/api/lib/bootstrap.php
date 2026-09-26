<?php
/**
 * Common bootstrap for every API endpoint.
 * - Loads config from environment variables (never from files in the web root)
 * - Hides errors from clients, logs them server-side
 * - Sends security headers
 */
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);
header_remove('X-Powered-By');

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/http.php';
require_once __DIR__ . '/validate.php';
require_once __DIR__ . '/ratelimit.php';
require_once __DIR__ . '/token.php';
require_once __DIR__ . '/mailer.php';
require_once __DIR__ . '/tier.php';

set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
    if (!(error_reporting() & $severity)) {
        return false;
    }
    throw new ErrorException($message, 0, $severity, $file, $line);
});

set_exception_handler(static function (Throwable $e): void {
    // Log the class/location only — never request bodies (they contain personal information).
    error_log(sprintf('[bigcat-api] %s at %s:%d — %s', get_class($e), basename($e->getFile()), $e->getLine(), $e->getMessage()));
    if (!headers_sent()) {
        send_security_headers();
        http_response_code(500);
        header('Content-Type: application/json; charset=utf-8');
    }
    echo json_encode(['ok' => false, 'message' => 'Something went wrong on our side. Please try again shortly.']);
});

send_security_headers();
