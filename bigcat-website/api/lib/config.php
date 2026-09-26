<?php
/**
 * Configuration comes ONLY from environment variables (set in PHP-FPM pool
 * config, the hosting control panel, or an env file OUTSIDE the web root
 * pointed to by BIGCAT_ENV_FILE). See .env.example. Never commit secrets.
 */
declare(strict_types=1);

/**
 * A directory inside the web root is acceptable ONLY if it carries an
 * .htaccess that denies all web access (shared hosting where the FTP account
 * cannot reach above the web root). Nginx denies /_private/ explicitly.
 */
function dir_is_locked(string $dir): bool
{
    $ht = $dir . '/.htaccess';
    return is_file($ht) && str_contains((string) file_get_contents($ht), 'Require all denied');
}

/** Candidate env file locations, most preferred first. */
function env_file_candidates(): array
{
    $list = [];
    $explicit = getenv('BIGCAT_ENV_FILE');
    if ($explicit) {
        $list[] = $explicit;
    }
    $docRoot = realpath($_SERVER['DOCUMENT_ROOT'] ?? '') ?: '';
    if ($docRoot !== '') {
        $list[] = dirname($docRoot) . '/bigcat-private/bigcat.env';   // outside the web root (preferred)
        $list[] = $docRoot . '/_private/bigcat.env';                   // locked folder inside the web root
    }
    return $list;
}

function bigcat_load_env_file(): void
{
    static $loaded = false;
    if ($loaded) {
        return;
    }
    $loaded = true;
    $docRoot = realpath($_SERVER['DOCUMENT_ROOT'] ?? '') ?: '';
    foreach (env_file_candidates() as $file) {
        if (!is_file($file) || !is_readable($file)) {
            continue;
        }
        $real = realpath($file) ?: '';
        if ($docRoot !== '' && str_starts_with($real, $docRoot . DIRECTORY_SEPARATOR) && !dir_is_locked(dirname($real))) {
            error_log('[bigcat-api] env file is inside the web root without a deny-all .htaccess — ignored.');
            continue;
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
        $GLOBALS['bigcat_env_dir'] = dirname($real);
        return;
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
    // Relative paths resolve next to the env file (handy on cPanel where the absolute path is unknown).
    if (!str_starts_with($dir, '/') && !preg_match('#^[A-Za-z]:[\\\\/]#', $dir) && isset($GLOBALS['bigcat_env_dir'])) {
        $dir = $GLOBALS['bigcat_env_dir'] . '/' . $dir;
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
