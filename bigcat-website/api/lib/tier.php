<?php
/**
 * Lead tier from suburb/town + state. Mirrors src/lib/tier.ts and uses the
 * same shared locality list (shared/greater-melbourne-localities.json,
 * deployed as api/lib/greater-melbourne-localities.json).
 */
declare(strict_types=1);

function melbourne_localities(): array
{
    static $set = null;
    if ($set !== null) {
        return $set;
    }
    $candidates = [
        __DIR__ . '/greater-melbourne-localities.json',
        dirname(__DIR__, 2) . '/shared/greater-melbourne-localities.json',
    ];
    foreach ($candidates as $file) {
        if (is_file($file)) {
            $data = json_decode((string) file_get_contents($file), true);
            if (is_array($data) && isset($data['localities']) && is_array($data['localities'])) {
                return $set = array_fill_keys($data['localities'], true);
            }
        }
    }
    error_log('[bigcat-api] greater-melbourne-localities.json not found; all VIC leads will tag regional_vic.');
    return $set = [];
}

function normalise_locality(string $v): string
{
    $s = mb_strtolower($v);
    $s = preg_replace('/\b(vic|victoria)\b/u', '', $s) ?? '';
    $s = preg_replace('/\b\d{4}\b/', '', $s) ?? '';
    $s = preg_replace("/[^a-z\\s'-]/", ' ', $s) ?? '';
    $s = preg_replace('/\bst\.?\s/', 'st ', $s) ?? '';
    $s = preg_replace('/\bmt\.?\s/', 'mount ', $s) ?? '';
    return trim(preg_replace('/\s+/', ' ', $s) ?? '');
}

/** @return 'melbourne'|'regional_vic'|'remote' */
function tier_for(string $suburb, string $state): string
{
    $st = strtoupper(trim($state));
    if ($st !== 'VIC' && $st !== 'VICTORIA') {
        return 'remote';
    }
    return isset(melbourne_localities()[normalise_locality($suburb)]) ? 'melbourne' : 'regional_vic';
}
