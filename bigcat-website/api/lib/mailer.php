<?php
/**
 * Minimal, dependency-free mailer with three transports:
 *   MAIL_TRANSPORT=smtp  — authenticated SMTP (STARTTLS or implicit TLS). Recommended.
 *   MAIL_TRANSPORT=mail  — PHP mail() via the host's sendmail.
 *   MAIL_TRANSPORT=log   — writes .eml files to STORAGE_DIR/mail-log (development/UAT only;
 *                          refused when APP_ENV=production; purged after 24h).
 *
 * Header injection is prevented by stripping CR/LF from every header value and
 * validating addresses. User-supplied addresses are only ever used in Reply-To,
 * never in To/From, so the form cannot be used as an open relay.
 */
declare(strict_types=1);

final class MailMessage
{
    public function __construct(
        public string $subject,
        public string $body,
        public ?string $replyTo = null,
    ) {
    }
}

function mail_configured(): bool
{
    $to = env('MAIL_TO');
    $from = env('MAIL_FROM');
    if ($to === null || $from === null || !valid_email($to) || !valid_email($from)) {
        return false;
    }
    $t = env('MAIL_TRANSPORT', 'smtp');
    if ($t === 'smtp') {
        return env('SMTP_HOST') !== null && env('SMTP_USER') !== null && env('SMTP_PASS') !== null;
    }
    if ($t === 'log') {
        return app_env() !== 'production' && storage_dir() !== null;
    }
    return $t === 'mail';
}

function send_team_mail(MailMessage $msg): bool
{
    if (!mail_configured()) {
        error_log('[bigcat-api] mail not configured');
        return false;
    }
    $to = (string) env('MAIL_TO');
    $from = (string) env('MAIL_FROM');
    $fromName = header_safe((string) env('MAIL_FROM_NAME', 'Big Cat Marketing Website'), 60);
    $subject = header_safe($msg->subject, 150);
    $replyTo = ($msg->replyTo !== null && valid_email($msg->replyTo)) ? $msg->replyTo : null;
    $body = str_replace(["\r\n", "\r"], "\n", $msg->body);

    $headers = [
        'Date' => date(DATE_RFC2822),
        'From' => encode_display_name($fromName) . " <$from>",
        'To' => "<$to>",
        'Subject' => mb_encode_mimeheader($subject, 'UTF-8', 'B', "\r\n"),
        'Message-ID' => '<' . bin2hex(random_bytes(12)) . '@' . (explode('@', $from)[1] ?? 'localhost') . '>',
        'MIME-Version' => '1.0',
        'Content-Type' => 'text/plain; charset=UTF-8',
        'Content-Transfer-Encoding' => '8bit',
        'X-Mailer' => 'BigCat-Website',
        'Auto-Submitted' => 'auto-generated',
    ];
    if ($replyTo !== null) {
        $headers['Reply-To'] = "<$replyTo>";
    }

    return match (env('MAIL_TRANSPORT', 'smtp')) {
        'smtp' => smtp_send($from, $to, $headers, $body),
        'log' => log_send($headers, $body),
        default => php_mail_send($to, $subject, $headers, $body, $from),
    };
}

function encode_display_name(string $name): string
{
    return preg_match('/^[\w .-]+$/', $name) ? '"' . $name . '"' : mb_encode_mimeheader($name, 'UTF-8', 'B');
}

/** @param array<string,string> $headers */
function php_mail_send(string $to, string $subject, array $headers, string $body, string $from): bool
{
    unset($headers['To'], $headers['Subject']);
    $h = [];
    foreach ($headers as $k => $v) {
        $h[] = $k . ': ' . str_replace(["\r", "\n"], '', $v);
    }
    return mail($to, mb_encode_mimeheader($subject, 'UTF-8', 'B', "\r\n"), $body, implode("\r\n", $h), '-f' . $from);
}

/** @param array<string,string> $headers */
function log_send(array $headers, string $body): bool
{
    if (app_env() === 'production') {
        return false;
    }
    $dir = storage_dir() . '/mail-log';
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    purge_old_files($dir, RATE_RETENTION_SECONDS);
    $h = '';
    foreach ($headers as $k => $v) {
        $h .= $k . ': ' . str_replace(["\r", "\n"], '', $v) . "\r\n";
    }
    return file_put_contents($dir . '/' . date('Ymd-His') . '-' . bin2hex(random_bytes(4)) . '.eml', $h . "\r\n" . $body) !== false;
}

/** @param array<string,string> $headers */
function smtp_send(string $from, string $to, array $headers, string $body): bool
{
    $host = (string) env('SMTP_HOST');
    $port = (int) env('SMTP_PORT', '587');
    $secure = env('SMTP_SECURE', $port === 465 ? 'ssl' : 'tls');
    $timeout = 10;
    $ctx = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'SNI_enabled' => true]]);
    $remote = ($secure === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port;
    $errno = 0;
    $errstr = '';
    $fp = @stream_socket_client($remote, $errno, $errstr, $timeout, STREAM_CLIENT_CONNECT, $ctx);
    if ($fp === false) {
        error_log("[bigcat-api] SMTP connect failed ($errno)");
        return false;
    }
    stream_set_timeout($fp, $timeout);
    $read = static function () use ($fp): string {
        $data = '';
        while (($line = fgets($fp, 515)) !== false) {
            $data .= $line;
            if (strlen($line) < 4 || $line[3] === ' ') {
                break;
            }
        }
        return $data;
    };
    $cmd = static function (string $c, array $okCodes) use ($fp, $read): bool {
        if ($c !== '') {
            fwrite($fp, $c . "\r\n");
        }
        $resp = $read();
        $ok = in_array((int) substr($resp, 0, 3), $okCodes, true);
        if (!$ok) {
            error_log('[bigcat-api] SMTP unexpected reply ' . substr($resp, 0, 3));
        }
        return $ok;
    };
    $ehloHost = preg_replace('/[^a-z0-9.-]/i', '', (string) (explode('@', $from)[1] ?? 'localhost'));
    try {
        if (!$cmd('', [220]) || !$cmd("EHLO $ehloHost", [250])) {
            return false;
        }
        if ($secure === 'tls') {
            if (!$cmd('STARTTLS', [220])) {
                return false;
            }
            if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT)) {
                error_log('[bigcat-api] SMTP STARTTLS failed');
                return false;
            }
            if (!$cmd("EHLO $ehloHost", [250])) {
                return false;
            }
        }
        if (!$cmd('AUTH LOGIN', [334])
            || !$cmd(base64_encode((string) env('SMTP_USER')), [334])
            || !$cmd(base64_encode((string) env('SMTP_PASS')), [235])) {
            return false;
        }
        if (!$cmd("MAIL FROM:<$from>", [250]) || !$cmd("RCPT TO:<$to>", [250, 251]) || !$cmd('DATA', [354])) {
            return false;
        }
        $h = '';
        foreach ($headers as $k => $v) {
            $h .= $k . ': ' . str_replace(["\r", "\n"], '', $v) . "\r\n";
        }
        $data = $h . "\r\n" . str_replace("\n", "\r\n", $body);
        $data = preg_replace('/^\./m', '..', $data); // dot-stuffing
        fwrite($fp, $data . "\r\n.\r\n");
        if (!$cmd('', [250])) {
            return false;
        }
        $cmd('QUIT', [221]);
        return true;
    } finally {
        fclose($fp);
    }
}

/** Render a plain-text key/value block for team notification emails. */
function format_fields(array $fields): string
{
    $out = '';
    foreach ($fields as $label => $value) {
        if (is_bool($value)) {
            $value = $value ? 'Yes' : 'No';
        }
        if (is_array($value)) {
            $value = $value ? json_encode($value, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) : '—';
        }
        $value = (string) $value;
        $out .= str_pad($label . ':', 22) . ($value === '' ? '—' : $value) . "\n";
    }
    return $out;
}
