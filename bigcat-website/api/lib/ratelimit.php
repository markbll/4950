<?php
/**
 * File-based sliding-window rate limiter. Stores only an HMAC of the client
 * IP (never the raw IP) plus timestamps, in STORAGE_DIR (outside the web
 * root). Files older than 24 hours are purged automatically.
 */
declare(strict_types=1);

const RATE_RETENTION_SECONDS = 86400;

function rate_limit_hit(string $bucket, string $ip, int $limit, int $windowSeconds): bool
{
    $dir = storage_dir();
    $secret = app_secret();
    if ($dir === null || $secret === null) {
        return false; // fail closed
    }
    $rlDir = $dir . '/ratelimit';
    if (!is_dir($rlDir)) {
        @mkdir($rlDir, 0700, true);
    }
    $key = hash_hmac('sha256', $bucket . '|' . $ip, $secret);
    $file = $rlDir . '/' . $key . '.json';
    $now = time();

    $fh = fopen($file, 'c+');
    if ($fh === false) {
        return false;
    }
    try {
        flock($fh, LOCK_EX);
        $raw = stream_get_contents($fh);
        $hits = json_decode($raw ?: '[]', true);
        $hits = is_array($hits) ? array_values(array_filter($hits, static fn($t) => is_int($t) && $t > $now - $windowSeconds)) : [];
        if (count($hits) >= $limit) {
            return false;
        }
        $hits[] = $now;
        ftruncate($fh, 0);
        rewind($fh);
        fwrite($fh, json_encode($hits));
        return true;
    } finally {
        flock($fh, LOCK_UN);
        fclose($fh);
        if (random_int(1, 20) === 1) {
            purge_old_files($rlDir, RATE_RETENTION_SECONDS);
        }
    }
}

function purge_old_files(string $dir, int $maxAgeSeconds): void
{
    $cutoff = time() - $maxAgeSeconds;
    foreach (glob($dir . '/*') ?: [] as $f) {
        if (is_file($f) && filemtime($f) < $cutoff) {
            @unlink($f);
        }
    }
}
