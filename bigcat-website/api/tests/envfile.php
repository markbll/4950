<?php
/** Separate process test for env-file discovery (config.php caches its load). Run by run.php. */
declare(strict_types=1);
$mode = $argv[1] ?? 'locked';
$root = sys_get_temp_dir() . '/bigcat-envtest-' . bin2hex(random_bytes(3));
mkdir("$root/web/_private", 0700, true);
file_put_contents("$root/web/_private/bigcat.env", "APP_SECRET=" . str_repeat('e', 40) . "\nSTORAGE_DIR=storage\n");
if ($mode === 'locked') {
    file_put_contents("$root/web/_private/.htaccess", "Require all denied\n");
}
$_SERVER['DOCUMENT_ROOT'] = "$root/web";
require __DIR__ . '/../lib/config.php';
$secret = app_secret();
$storage = storage_dir();
echo json_encode(['secret' => $secret !== null, 'storage' => $storage === realpath("$root/web/_private") . '/storage']);
