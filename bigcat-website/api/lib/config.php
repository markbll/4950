<?php
/**
 * Configuration comes ONLY from environment variables (set in PHP-FPM pool
 * config, the hosting control panel, or an env file OUTSIDE the web root
 * pointed to by BIGCAT_ENV_FILE). See .env.example. Never commit secrets.
 */
declare(strict_types=1);

function bigcat_load_env_file(): void
{
    static $loaded = false;
    if ($loaded) {
        return;
    }
    $loaded = true;
    $file = getenv('BIGCAT_ENV_FILE') ?: '';
    if ($file === '' || !is_file($file) || !is_readable($file)) {
        return;
    }
    // Refuse env files inside the document root.
    $docRoot = realpath($_SERVER['DOCUMENT_ROOT'] ?? '') ?: null;
    $real = realpath($file) ?: '';
    if ($docRoot !== null && $docRoot !== '' && str_starts_with($real, $docRoot . DIRECTORY_SEPARATOR)) {
        error_log('[bigcat-api] BIGCAT_ENV_FILE is inside the document root — ignored.');
        return;
    }
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
            continue;
        }
        [$k, $v] = array_map('trim', explode('=', $line, 2));
        if (!preg_match('/^[A-Z][A-Z0-9_]*$/', $k)) {
            continue;
        }
        $v = trim($v, "\"'");
        if (getenv($k) === false) {
            putenv("$k=$v");
        }
    }
}

function env(string $key, ?string $default = null): ?string
{
    bigcat_load_env_file();
    $v = getenv($key);
    if ($v === false || $v === '') {
        return $default;
    }
    return $v;
}

function app_env(): string
{
    $e = env('APP_ENV', 'production');
    return in_array($e, ['production', 'staging', 'development'], true) ? $e : 'production';
}

function app_secret(): ?string
{
    $s = env('APP_SECRET');
    return ($s !== null && strlen($s) >= 32) ? $s : null;
}

function storage_dir(): ?string
{
    $dir = env('STORAGE_DIR');
    if ($dir === null) {
        return null;
    }
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    return is_dir($dir) && is_writable($dir) ? rtrim($dir, '/\\') : null;
}

/** @return string[] */
function allowed_origins(): array
{
    $raw = env('ALLOWED_ORIGINS', '');
    return array_values(array_filter(array_map(static fn($o) => rtrim(trim($o), '/'), explode(',', (string) $raw))));
}
