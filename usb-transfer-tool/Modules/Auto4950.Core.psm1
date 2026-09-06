<#
.SYNOPSIS
    Auto 49/50 - USB Compression & Transfer Tool - Core function library.

.DESCRIPTION
    Runspace-safe helper functions used by both the GUI (main runspace) and the
    background worker runspaces. Contains NO WPF/UI code so it can be imported
    anywhere. Covers:
        * Configuration load / save / validation
        * 7-Zip discovery and archive creation
        * SHA-256 / MD5 hashing and manifest generation
        * Network-share transfer (robocopy with Copy-Item fallback) + verification
        * Live system statistics (CPU, RAM, network, temp-folder space)
        * Structured logging

    Author : Auto4950 Tooling
    Licence : Internal use
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ------------------------------------------------------------ Configuration

# Default configuration used when no config file exists yet.
function Get-DefaultConfig {
    [CmdletBinding()]
    param()
    [ordered]@{
        # --- Destination -------------------------------------------------------
        NetworkShare        = 'C:\Destination'         # UNC share or local folder files are transferred to
        # --- Tooling -----------------------------------------------------------
        SevenZipPath        = ''                       # Auto-detected if blank
        # --- Case / naming -----------------------------------------------------
        CasePrefix          = 'CMS-A'                  # Enforced prefix for case numbers
        # --- Compression -------------------------------------------------------
        CompressionLevel    = 5                        # 0 (store) .. 9 (ultra)
        ArchiveFormat       = 'zip'                     # zip | 7z - only honoured when VolumeSizeMB is 0; a split always forces 7z (see New-A4950Archive)
        VolumeSizeMB        = 2048                      # Split archives into volumes of this size (MB). 0 = no split
        TransferMode        = 'OnComplete'              # OnComplete | Instant - see New-A4950Archive
        Password            = ''                       # Optional AES-256 archive password (blank = none)
        # --- Hashing -----------------------------------------------------------
        HashAlgorithms      = @('SHA256', 'MD5')       # Original-file hashing
        EmbedManifest       = $true                    # Include hash manifest inside each archive
        # --- Behaviour ---------------------------------------------------------
        AutoPromptOnInsert  = $true                    # Show the action prompt when a USB drive appears
        DefaultSelectAll    = $true                    # Pre-select all folders/files by default
        VerifyAfterTransfer = $true                    # Re-hash the archive at destination
        StagingFolder       = 'C:\temp'                # Where archives are staged before transfer
        SlowMachineMode     = $false                   # Low CPU/RAM/GPU mode: no system monitor, single-threaded compression
        # --- Sounds --------------------------------------------------------------
        SoundStartPath      = ''                       # Optional .wav played when a job starts (blank = a plain beep)
        SoundFinishPath     = ''                       # Optional .wav played when a job finishes (blank = Windows Asterisk)
        SoundErrorPath      = ''                       # Optional .wav played on error (blank = Windows Hand/Critical Stop)
        # --- Appearance ----------------------------------------------------------
        FontSize            = 'Medium'                 # Small | Medium | Large | ExtraLarge
        DarkMode            = $true                    # $false switches to a light theme
        # --- Excludes ----------------------------------------------------------
        ExcludePatterns     = @('System Volume Information', '$RECYCLE.BIN', 'Thumbs.db')
    }
}

function Expand-A4950Path {
    <#
    .SYNOPSIS Expand environment-variable references in a path string.
    .DESCRIPTION
        Understands both Windows '%VAR%' syntax and PowerShell's '$env:VAR'
        syntax. The latter is expanded automatically ONLY when it appears
        inside a double-quoted string literal in PowerShell source code - a
        value loaded from JSON is just data, so a saved "$env:TEMP\x" stays
        completely literal. Passed as-is to a path/provider cmdlet, PowerShell
        then tries to resolve a PSDrive literally named "$env" and fails with
        "Cannot find drive. A drive with the name '$env' does not exist."
        This expands both forms so a saved config value is safe either way.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $result = $Path
    $opts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    foreach ($m in [regex]::Matches($Path, '\$env:([A-Za-z_][A-Za-z0-9_]*)', $opts)) {
        $val = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
        if ($null -ne $val) { $result = $result.Replace($m.Value, $val) }
    }
    return [Environment]::ExpandEnvironmentVariables($result)
}

function Get-ConfigPath {
    [CmdletBinding()]
    param([string]$Root)
    if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
    Join-Path $Root 'config.json'
}

function Import-A4950Config {
    <#
    .SYNOPSIS Load configuration from config.json, falling back to defaults.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { $Path = Get-ConfigPath }
    $config = Get-DefaultConfig

    if (Test-Path -LiteralPath $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $raw.PSObject.Properties) {
                # Overlay saved values onto the default template (keeps new keys).
                $config[$p.Name] = $p.Value
            }
        } catch {
            Write-Warning "Failed to parse '$Path': $($_.Exception.Message). Using defaults."
        }
    }
    # Expand environment variables inside path-like values (repairs any
    # previously-saved '$env:...' literal too - see Expand-A4950Path).
    $config['StagingFolder'] = Expand-A4950Path $config['StagingFolder']
    return $config
}

function Save-A4950Config {
    <#
    .SYNOPSIS Persist configuration to config.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [string]$Path
    )
    if (-not $Path) { $Path = Get-ConfigPath }
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Test-A4950Config {
    <#
    .SYNOPSIS Validate a configuration object. Returns a list of problem strings (empty = OK).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config)

    $issues = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($Config.NetworkShare)) {
        $issues.Add('Destination is not set.')
    }
    $sz = Resolve-SevenZip -PreferredPath $Config.SevenZipPath
    if (-not $sz) {
        $issues.Add('7-Zip (7z.exe) could not be located. Install it or set SevenZipPath.')
    }
    if ($Config.CompressionLevel -lt 0 -or $Config.CompressionLevel -gt 9) {
        $issues.Add('CompressionLevel must be between 0 and 9.')
    }
    if (-not $Config.CasePrefix) {
        $issues.Add('CasePrefix must not be empty.')
    }
    return $issues
}

#endregion

#region ------------------------------------------------------------ 7-Zip discovery / compression

function Resolve-SevenZip {
    <#
    .SYNOPSIS Locate the 7-Zip command-line executable.
    .DESCRIPTION
        The 7-Zip installer does NOT add itself to PATH, so detection can't rely
        on Get-Command alone. This checks, in order:
          1. An explicit preferred path (from config).
          2. The registry install path the 7-Zip installer writes (most reliable).
          3. PATH (Get-Command), in case it was added manually.
          4. Common install locations (Program Files, per-user, winget, choco, scoop).
          5. The uninstall registry's InstallLocation.
          6. A bounded search of the Program Files 7-Zip folders.
        Falls back to the standalone 7za.exe if the full 7z.exe isn't present.
    #>
    [CmdletBinding()]
    param([string]$PreferredPath)

    function Test-Exe([string]$p) { $p -and (Test-Path -LiteralPath $p -PathType Leaf) }

    # 1. Explicit preferred path (accept a folder too).
    if ($PreferredPath) {
        if (Test-Exe $PreferredPath) { return $PreferredPath }
        $j = Join-Path $PreferredPath '7z.exe'
        if (Test-Exe $j) { return $j }
    }

    # 2. Registry install path (HKLM/HKCU, native + WOW6432Node). Path64 preferred.
    $regKeys = @(
        'HKLM:\SOFTWARE\7-Zip'
        'HKLM:\SOFTWARE\WOW6432Node\7-Zip'
        'HKCU:\SOFTWARE\7-Zip'
    )
    foreach ($k in $regKeys) {
        try {
            $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            if ($props) {
                $vals = @()
                # Index the properties collection (StrictMode-safe: absent = $null, no throw).
                if ($props.PSObject.Properties['Path64']) { $vals += $props.Path64 }
                if ($props.PSObject.Properties['Path'])   { $vals += $props.Path }
                foreach ($val in $vals) {
                    if ($val) {
                        $exe = Join-Path $val '7z.exe'
                        if (Test-Exe $exe) { return $exe }
                    }
                }
            }
        } catch {}
    }

    # 3. On PATH (only if the user added it).
    $cmd = Get-Command '7z.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    # 4. Common install locations.
    $dirs = @(
        $env:ProgramW6432
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        "$env:LOCALAPPDATA\Programs"
        "$env:ProgramData\chocolatey\bin"
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
        "$env:USERPROFILE\scoop\shims"
        "$env:USERPROFILE\scoop\apps\7zip\current"
    ) | Where-Object { $_ }
    foreach ($d in $dirs) {
        foreach ($exe in @('7z.exe', '7za.exe')) {
            $p1 = Join-Path $d "7-Zip\$exe"
            $p2 = Join-Path $d $exe
            if (Test-Exe $p1) { return $p1 }
            if (Test-Exe $p2) { return $p2 }
        }
    }

    # 5. Uninstall registry InstallLocation.
    $uninst = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip'
    )
    foreach ($k in $uninst) {
        try {
            $up = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            if ($up -and $up.PSObject.Properties['InstallLocation'] -and $up.InstallLocation) {
                $exe = Join-Path $up.InstallLocation '7z.exe'
                if (Test-Exe $exe) { return $exe }
            }
        } catch {}
    }

    # 6. Bounded search under Program Files (last resort; fast, top 2 levels).
    foreach ($base in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique) {
        try {
            $hit = Get-ChildItem -Path $base -Filter '7z.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch {}
    }

    return $null
}

function Invoke-A4950Process {
    <#
    .SYNOPSIS Run an external process with cancellation support.
    .DESCRIPTION
        Starts a process, drains stdout/stderr asynchronously (no deadlock),
        and polls -CancelCheck every 150 ms. On cancel it kills the whole
        process tree so the operation stops almost immediately. -OnTick, if
        given, is also called on each ~150 ms poll while the process is still
        running - used by New-A4950Archive's Instant transfer mode to notice
        newly-finished archive volumes while 7-Zip is still working.
        Returns @{ ExitCode; Cancelled; Output }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [scriptblock]$CancelCheck,
        [scriptblock]$OnTick
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    # Quote arguments that contain spaces or quotes so paths survive intact.
    $psi.Arguments = (($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' ')
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    # Async drain prevents the child from blocking on a full pipe buffer.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $cancelled = $false
    while (-not $proc.WaitForExit(150)) {
        if ($CancelCheck -and (& $CancelCheck)) {
            $cancelled = $true
            try { & taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null } catch {}
            try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
            break
        }
        if ($OnTick) { & $OnTick }
    }
    try { $proc.WaitForExit(3000) | Out-Null } catch {}

    $out = ''
    try { $out = $outTask.Result } catch {}
    $err = ''
    try { $err = $errTask.Result } catch {}
    $exit = -1
    try { $exit = $proc.ExitCode } catch {}
    $proc.Dispose()

    return [pscustomobject]@{
        ExitCode  = $exit
        Cancelled = $cancelled
        Output    = ($out + "`n" + $err)
    }
}

function New-A4950Archive {
    <#
    .SYNOPSIS Create a 7-Zip archive from a source path.
    .DESCRIPTION
        Wraps 7z.exe. Returns a result object with Success, ArchivePath and Output.
        Streams 7z stdout to the optional -OnOutput scriptblock for live logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SevenZipPath,
        [Parameter(Mandatory)][string[]]$SourcePath,   # one path, or several to combine into one archive
        [Parameter(Mandatory)][string]$ArchivePath,
        [ValidateRange(0, 9)][int]$Level = 5,
        [ValidateSet('7z', 'zip')][string]$Format = 'zip',
        [int]$VolumeSizeMB = 0,          # >0 splits the archive into volumes of this size (MB)
        [string]$Password,
        [string[]]$ExcludePatterns,
        [string[]]$ExtraFiles,          # Additional files to add (e.g. the manifest)
        [scriptblock]$CancelCheck,      # Return $true to abort (kills 7-Zip)
        [scriptblock]$OnPartReady,      # Called with a produced file's path as soon as it is complete
        [scriptblock]$OnOutput,
        [switch]$LowResource,           # Slow Machine Mode: single-threaded, capped compression level
        [ValidateSet('OnComplete', 'Instant')][string]$TransferMode = 'OnComplete'
    )

    # 7-Zip's -v (volumes) switch only splits the native 7z container - it
    # silently does NOT split zip archives (7z.exe just writes one whole .zip
    # and exits 0, ignoring -v entirely). Worse, a home-rolled raw byte split
    # of a zip is not verifiable by a receiver: 7-Zip only ever reports a
    # genuine, end-of-archive-header-checked "Volumes = N" for its own native
    # multi-volume format - given a partial set of raw byte-split files, `7z l`
    # instead just counts however many sequentially-numbered files happen to
    # be physically present and reports THAT as the total, with no validation
    # that it's really complete. So whenever the archive needs to be split
    # into volumes, it is always built as native 7z, regardless of the
    # requested Format - only that gives a receiving tool a volume count (and
    # a `7z t` pass) that can actually be trusted. An unsplit archive is
    # unaffected and still honours Format.
    $effectiveFormat = if ($VolumeSizeMB -gt 0) { '7z' } else { $Format }
    if ($effectiveFormat -ne $Format) {
        # 7-Zip keeps whatever extension it's given regardless of -t, so the
        # output file name must be corrected too - otherwise 7z-format volumes
        # would misleadingly still be named "*.zip.001".
        $ArchivePath = [System.IO.Path]::ChangeExtension($ArchivePath, '7z')
    }

    $archiveDir = Split-Path -Parent $ArchivePath
    if (-not (Test-Path -LiteralPath $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }
    $archiveLeaf = Split-Path -Leaf $ArchivePath
    # TrimEnd('.') is defensive: a base name ending in a dot (however it got
    # there) would otherwise leave a stray "..7z" double-dot once the "."
    # separator is appended back for the extension.
    $baseLeaf = ([System.IO.Path]::GetFileNameWithoutExtension($ArchivePath)).TrimEnd('.')

    # Remove any stale output from a previous run so volume detection is clean.
    Get-ChildItem -LiteralPath $archiveDir -Filter "$baseLeaf.*" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Build 7z argument list.  'a' = add, -mx = level, -t = type.
    # Multiple -SourcePath entries are added to the SAME archive in one pass,
    # so several selected folders/files end up combined into a single archive.
    #
    # Slow Machine Mode trades compression ratio for the smallest possible CPU
    # footprint: store (no compression math, just I/O) and single-threaded,
    # regardless of the Level/format the operator has set. Hashing, manifest
    # and verification are unaffected - only the compression cost changes.
    $effectiveLevel = if ($LowResource) { 0 } else { $Level }
    $szArgs = [System.Collections.Generic.List[string]]::new()
    $szArgs.AddRange([string[]]@('a', "-t$effectiveFormat", "-mx=$effectiveLevel", '-y', $ArchivePath))
    foreach ($sp in $SourcePath) { $szArgs.Add($sp) }
    if ($LowResource) { $szArgs.Add('-mmt=off') } else { $szArgs.Add('-mmt=on') }   # multi-threaded compression - 7-Zip supports this for both zip (deflate) and 7z
    if ($VolumeSizeMB -gt 0) { $szArgs.Add("-v${VolumeSizeMB}m") }   # 7z native volumes - always native now, see $effectiveFormat above
    if ($ExtraFiles)      { foreach ($ef in $ExtraFiles) { $szArgs.Add($ef) } }
    if ($Password) {
        $szArgs.Add("-p$Password")
        if ($effectiveFormat -eq '7z') { $szArgs.Add('-mhe=on') }      # encrypt headers too
    }
    if ($ExcludePatterns) {
        foreach ($x in $ExcludePatterns) { $szArgs.Add("-xr!$x") }
    }

    $result = [pscustomobject]@{
        Success     = $false
        Cancelled   = $false
        ArchivePath = $ArchivePath
        Format      = $effectiveFormat   # what was actually written - can differ from the requested Format when split
        Files       = @()               # actual output file(s): the archive, or its volume parts
        IsSplit     = ($VolumeSizeMB -gt 0)
        ExitCode    = -1
        Output      = ''
    }

    # Instant transfer mode: while 7-Zip is still running, poll for volumes it
    # has already finished writing and report them via -OnPartReady right
    # away, instead of waiting for the whole archive. 7-Zip's own writing
    # behaviour makes this safe: each volume is written to a "<name>.tmp"
    # file and only renamed to its final "<base>.7z.NNN" name once its
    # content is completely flushed and will never be touched again -
    # confirmed empirically against real 7-Zip 23.01, timestamping every
    # volume rename during a live multi-volume compress. The one volume this
    # can never speed up is .001: 7-Zip defers finalising it until the very
    # end (the archive's start header can only be written once the whole
    # body is known), at the same instant as the last volume - so .001 is
    # always excluded here and only ever reported in the final batch below,
    # which also matches the existing "always transfer .001 last" behaviour.
    # A same-name volume is never reported twice: $reportedVols is checked
    # again in the final batch below, after 7-Zip has fully exited.
    $reportedVols = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $onTick = $null
    if ($TransferMode -eq 'Instant' -and $VolumeSizeMB -gt 0 -and $OnPartReady) {
        $onTick = {
            $found = Get-ChildItem -LiteralPath $archiveDir -Filter "$archiveLeaf.*" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.\d{3}$' -and $_.Name -notmatch '\.001$' -and -not $reportedVols.Contains($_.Name) }
            foreach ($f in $found) {
                # Defense in depth beyond the .tmp-name signal above: confirm
                # nothing else still has the file open for writing before
                # treating it as safe to move. Best-effort - reliable file
                # locking semantics are OS-specific, so this is a second
                # check on top of (never a replacement for) the rename signal.
                $locked = $true
                try { ([System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)).Dispose(); $locked = $false } catch {}
                if ($locked) { continue }
                [void]$reportedVols.Add($f.Name)
                & $OnPartReady $f.FullName
            }
        }.GetNewClosure()
    }

    $run = Invoke-A4950Process -FilePath $SevenZipPath -Arguments $szArgs -CancelCheck $CancelCheck -OnTick $onTick
    $result.ExitCode  = $run.ExitCode
    $result.Output    = $run.Output
    $result.Cancelled = $run.Cancelled
    if ($OnOutput -and $run.Output) { & $OnOutput $run.Output }
    if ($run.Cancelled) {
        # Remove any partial output so nothing half-written is left behind.
        Get-ChildItem -LiteralPath $archiveDir -Filter "$archiveLeaf*" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        return $result
    }

    # Final, authoritative pass: every volume (or the unsplit archive) is only
    # KNOWN to exist, and only guaranteed complete, once 7z.exe has fully
    # exited - the process is a black box while running. In OnComplete mode
    # (the default) nothing was reported above, so every volume is reported
    # here, together, in one batch. In Instant mode most volumes were already
    # reported live as 7-Zip finished each one (see $onTick above); this pass
    # picks up whatever wasn't - always including .001, and covering the
    # OnComplete case identically to before. Volumes are left exactly as
    # 7-Zip names them - "<base>.7z.001", "<base>.7z.002", ... - so the
    # on-disk name always signals the real container format, and a receiver
    # testing them with `7z t`/`7z l` gets 7-Zip's own genuine, verified
    # volume count.
    if ($VolumeSizeMB -gt 0) {
        $vols = Get-ChildItem -LiteralPath $archiveDir -Filter "$archiveLeaf.*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.\d{3}$' } | Sort-Object Name
        if ($vols) { $result.Files = @($vols.FullName) }
        elseif (Test-Path -LiteralPath $ArchivePath) { $result.Files = @($ArchivePath) }  # not actually split
    } else {
        if (Test-Path -LiteralPath $ArchivePath) { $result.Files = @($ArchivePath) }
    }
    if ($OnPartReady) {
        foreach ($f in $result.Files) {
            if ($reportedVols.Contains((Split-Path -Leaf $f))) { continue }   # already reported live, above
            & $OnPartReady $f
        }
    }

    # 7-Zip exit codes: 0 = OK, 1 = warning (still usable).
    $result.Success = ($result.ExitCode -in 0, 1) -and ($result.Files.Count -gt 0)
    return $result
}

#endregion

#region ------------------------------------------------------------ Hashing / manifest

function Get-A4950FileHashes {
    <#
    .SYNOPSIS Compute the requested hash algorithms for a single file.
    .OUTPUTS Hashtable keyed by algorithm name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Algorithms = @('SHA256', 'MD5')
    )
    # Single-pass streaming hash: when SHA-256 and MD5 are both requested
    # (the default), reading the file once and feeding both hashers per
    # chunk avoids reading a large file from disk twice.
    $out = @{}
    $hashers = @{}
    foreach ($alg in $Algorithms) {
        $hashers[$alg] = switch ($alg) {
            'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
            'MD5'    { [System.Security.Cryptography.MD5]::Create() }
            default  { [System.Security.Cryptography.HashAlgorithm]::Create($alg) }
        }
    }
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] 1MB
            $read = 0
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                foreach ($h in $hashers.Values) { $h.TransformBlock($buffer, 0, $read, $null, 0) | Out-Null }
            }
            $empty = [byte[]]::new(0)
            foreach ($h in $hashers.Values) { $h.TransformFinalBlock($empty, 0, 0) | Out-Null }
            foreach ($alg in $Algorithms) {
                $out[$alg] = [System.BitConverter]::ToString($hashers[$alg].Hash).Replace('-', '')
            }
        } finally {
            $stream.Dispose()
        }
    } catch {
        $msg = "ERROR: $($_.Exception.Message)"
        foreach ($alg in $Algorithms) { $out[$alg] = $msg }
    } finally {
        foreach ($h in $hashers.Values) { $h.Dispose() }
    }
    return $out
}

function New-A4950Manifest {
    <#
    .SYNOPSIS Hash every file under one or more source paths and write a manifest file.
    .DESCRIPTION
        Produces a human-readable manifest and returns the manifest path plus the
        list of hashed records. Reports progress via -OnProgress { param($current,$total,$file) }.
        When multiple -SourcePath entries are given (combined-archive mode), each
        file's relative path is prefixed with its top-level item's own name so
        files from different selections stay distinguishable and never collide.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$SourcePath,
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$CaseNumber = '',
        [string[]]$Algorithms = @('SHA256', 'MD5'),
        [scriptblock]$OnProgress
    )

    # Gather (File, Root, Label) tuples across all source paths first, so a
    # single running total/percentage can be reported for the whole set.
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($root in $SourcePath) {
        $label = Split-Path -Leaf ($root.TrimEnd('\', '/'))
        if (-not $label) { $label = $root }
        if (Test-Path -LiteralPath $root -PathType Container) {
            $kids = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue
            foreach ($f in $kids) { $entries.Add([pscustomobject]@{ File = $f; Root = $root; Label = $label }) }
        } elseif (Test-Path -LiteralPath $root) {
            $entries.Add([pscustomobject]@{ File = (Get-Item -LiteralPath $root); Root = $root; Label = $label })
        }
    }

    $multi = @($SourcePath).Count -gt 1
    $records = New-Object System.Collections.Generic.List[object]
    $total = $entries.Count
    $i = 0
    foreach ($e in $entries) {
        $i++
        $f = $e.File
        if ($OnProgress) { & $OnProgress $i $total $f.FullName }
        $h = Get-A4950FileHashes -Path $f.FullName -Algorithms $Algorithms
        $rel = $f.FullName
        if ($f.FullName -eq $e.Root) {
            # The selected item IS this file (a standalone file was ticked,
            # not a folder) - nothing to append beyond its own name.
            $rel = ''
        } elseif ($f.FullName.Length -gt $e.Root.Length -and $f.FullName.StartsWith($e.Root)) {
            $rel = $f.FullName.Substring($e.Root.Length).TrimStart('\', '/')
        }
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = $f.Name }
        # Disambiguate across combined top-level items - but not when $rel is
        # already just the label (a standalone file), which would otherwise
        # duplicate it, e.g. "IMG_001.jpg\IMG_001.jpg".
        if ($multi -and $rel -ne $e.Label) { $rel = "$($e.Label)\$rel" }
        $rec = [ordered]@{
            RelativePath = $rel
            SizeBytes    = $f.Length
            Modified     = $f.LastWriteTimeUtc.ToString('o')
        }
        foreach ($alg in $Algorithms) { $rec[$alg] = $h[$alg] }
        $records.Add([pscustomobject]$rec)
    }

    # Write a clear, forensics-friendly manifest.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Auto4950 USB Transfer - Hash Manifest')
    [void]$sb.AppendLine('========================================')
    [void]$sb.AppendLine("Case Number   : $CaseNumber")
    [void]$sb.AppendLine("Source        : $($SourcePath -join '; ')")
    [void]$sb.AppendLine("Generated UTC : $([DateTime]::UtcNow.ToString('o'))")
    [void]$sb.AppendLine("Machine       : $env:COMPUTERNAME")
    [void]$sb.AppendLine("Operator      : $env:USERNAME")
    [void]$sb.AppendLine("File Count    : $total")
    [void]$sb.AppendLine("Algorithms    : $($Algorithms -join ', ')")
    [void]$sb.AppendLine('')
    foreach ($r in $records) {
        [void]$sb.AppendLine("FILE : $($r.RelativePath)")
        [void]$sb.AppendLine("  Size     : $($r.SizeBytes) bytes")
        [void]$sb.AppendLine("  Modified : $($r.Modified)")
        foreach ($alg in $Algorithms) { [void]$sb.AppendLine("  $($alg.PadRight(8)): $($r.$alg)") }
        [void]$sb.AppendLine('')
    }

    $dir = Split-Path -Parent $ManifestPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $sb.ToString() | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    # Also emit a CSV alongside for machine parsing.
    $csvPath = [IO.Path]::ChangeExtension($ManifestPath, 'csv')
    $records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        ManifestPath = $ManifestPath
        CsvPath      = $csvPath
        Records      = $records
        FileCount    = $total
    }
}

#endregion

#region ------------------------------------------------------------ Transfer

function Copy-A4950ToShare {
    <#
    .SYNOPSIS Copy a file to the destination share, preferring robocopy for resilience.
    .DESCRIPTION Cancellable: -CancelCheck aborts and kills robocopy near-instantly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceFile,
        [Parameter(Mandatory)][string]$DestinationFolder,
        [string]$TimeStamp,             # used to de-dupe a name that already exists at the destination
        [scriptblock]$CancelCheck,
        [scriptblock]$OnOutput
    )

    $result = [pscustomobject]@{ Success = $false; Cancelled = $false; ExitCode = -1; Destination = $null; Renamed = $false; Error = '' }
    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }

        $srcDir   = Split-Path -Parent $SourceFile
        $srcName  = Split-Path -Leaf   $SourceFile
        $destName = $srcName

        # Fault handling: never overwrite an existing destination file. If a file
        # of the same name is already there, append the date/time to make it unique.
        if (Test-Path -LiteralPath (Join-Path $DestinationFolder $srcName)) {
            if (-not $TimeStamp) { $TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss' }
            $destName = Get-A4950UniqueName -FileName $srcName -Folder $DestinationFolder -TimeStamp $TimeStamp
            $result.Renamed = $true
        }
        $result.Destination = Join-Path $DestinationFolder $destName

        $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
        if ($robocopy -and $destName -eq $srcName) {
            # robocopy keeps the same file name; fast path.
            # /Z = restartable mode - a dropped network connection resumes
            # from the last checkpoint instead of re-copying the whole file.
            # /J = unbuffered I/O for large sequential files.
            $rcArgs = @($srcDir, $DestinationFolder, $srcName, '/Z', '/J', '/R:2', '/W:3', '/NP', '/NDL', '/NJH', '/NJS')
            $run = Invoke-A4950Process -FilePath $robocopy.Source -Arguments $rcArgs -CancelCheck $CancelCheck
            $result.ExitCode  = $run.ExitCode
            $result.Cancelled = $run.Cancelled
            if ($OnOutput -and $run.Output) { & $OnOutput $run.Output }
            $result.Success = (-not $run.Cancelled) -and ($run.ExitCode -lt 8) -and (Test-Path -LiteralPath $result.Destination)
        } else {
            # Renamed target (or no robocopy): copy to the explicit destination name.
            if ($CancelCheck -and (& $CancelCheck)) { $result.Cancelled = $true; return $result }
            Copy-Item -LiteralPath $SourceFile -Destination $result.Destination -Force
            $result.ExitCode = 0
            $result.Success = Test-Path -LiteralPath $result.Destination
        }
        if ($result.Cancelled) {
            Remove-Item -LiteralPath $result.Destination -Force -ErrorAction SilentlyContinue
        }
    } catch {
        $result.Error = $_.Exception.Message
        $result.Success = $false
    }
    return $result
}

function Get-A4950UniqueName {
    <#
    .SYNOPSIS Build a destination file name that does not already exist, by
              inserting a date/time stamp before the first extension.
    .EXAMPLE  case__Photos.001  ->  case__Photos_20260727_143000.001
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Folder,
        [string]$TimeStamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
    )
    $dot = $FileName.IndexOf('.')
    if ($dot -lt 0) { $base = $FileName; $ext = '' } else { $base = $FileName.Substring(0, $dot); $ext = $FileName.Substring($dot) }
    $candidate = "${base}_${TimeStamp}${ext}"
    $i = 1
    while (Test-Path -LiteralPath (Join-Path $Folder $candidate)) {
        $candidate = "${base}_${TimeStamp}_$i${ext}"   # extremely unlikely, but stay safe
        $i++
    }
    return $candidate
}

function Write-A4950TransferLog {
    <#
    .SYNOPSIS Write a transfer log (optionally a "failed transfer" log) listing
              the files that reached the destination, with hash, size and time.
    .OUTPUTS The log file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)]$Records,       # objects: Name, Sha256, SizeBytes, TransferredUtc
        [string]$Reference = '',
        [switch]$Failed,
        [string]$Source = '',
        [string]$Destination = '',
        $StartTime = $null,                  # [DateTime], local time
        $FinishTime = $null,                 # [DateTime], local time
        [int]$FileCount = 0,                 # original (uncompressed) file count
        [int]$FolderCount = 0,               # original folder count
        [int64]$TotalBytes = 0,              # original (uncompressed) total size
        [int64]$CompressedBytes = 0          # size actually written to the destination (archive/volumes)
    )
    $sb = New-Object System.Text.StringBuilder
    if ($Failed) {
        [void]$sb.AppendLine('*** THESE FILES ARE FROM A FAILED TRANSFER ***')
        [void]$sb.AppendLine('The transfer was cancelled or did not complete. The files listed below')
        [void]$sb.AppendLine('were already copied to the destination before it stopped.')
    } else {
        [void]$sb.AppendLine('Auto 49/50 - Transfer Log (completed)')
    }
    [void]$sb.AppendLine('==========================================================')
    [void]$sb.AppendLine("Reference     : $Reference")
    if ($Source)      { [void]$sb.AppendLine("Source        : $Source") }
    if ($Destination) { [void]$sb.AppendLine("Destination   : $Destination") }
    if ($StartTime)   { [void]$sb.AppendLine("Started       : $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))") }
    if ($FinishTime)  { [void]$sb.AppendLine("Finished      : $($FinishTime.ToString('yyyy-MM-dd HH:mm:ss'))") }
    [void]$sb.AppendLine("Generated UTC : $([DateTime]::UtcNow.ToString('o'))")
    [void]$sb.AppendLine("Machine       : $env:COMPUTERNAME")
    [void]$sb.AppendLine("Operator      : $env:USERNAME")
    [void]$sb.AppendLine("Original      : $FileCount file(s), $FolderCount folder(s), $(Format-A4950Bytes $TotalBytes)")
    [void]$sb.AppendLine("Compressed    : $(Format-A4950Bytes $CompressedBytes)")
    [void]$sb.AppendLine("Files copied  : $(@($Records).Count)")
    [void]$sb.AppendLine('')
    foreach ($r in @($Records)) {
        [void]$sb.AppendLine("FILE : $($r.Name)")
        [void]$sb.AppendLine("  Size          : $($r.SizeBytes) bytes")
        [void]$sb.AppendLine("  SHA-256       : $($r.Sha256)")
        [void]$sb.AppendLine("  TransferredUTC: $($r.TransferredUtc)")
        [void]$sb.AppendLine('')
    }
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $sb.ToString() | Set-Content -LiteralPath $LogPath -Encoding UTF8
    return $LogPath
}

function Test-A4950TransferIntegrity {
    <#
    .SYNOPSIS Verify a transferred file matches the source by SHA-256.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceFile,
        [Parameter(Mandatory)][string]$DestinationFile
    )
    if (-not (Test-Path -LiteralPath $DestinationFile)) {
        return [pscustomobject]@{ Match = $false; Reason = 'Destination file missing' }
    }
    $s = (Get-FileHash -LiteralPath $SourceFile -Algorithm SHA256).Hash
    $d = (Get-FileHash -LiteralPath $DestinationFile -Algorithm SHA256).Hash
    return [pscustomobject]@{
        Match       = ($s -eq $d)
        SourceHash  = $s
        DestHash    = $d
        Reason      = if ($s -eq $d) { 'OK' } else { 'SHA-256 mismatch' }
    }
}

#endregion

#region ------------------------------------------------------------ System statistics

function Get-A4950SystemStats {
    <#
    .SYNOPSIS Snapshot CPU %, memory, network throughput and temp-folder free space.
    .DESCRIPTION
        Network throughput is computed from the delta against -Previous (a prior
        return value). Pass the previous snapshot to get a per-second rate.
    #>
    [CmdletBinding()]
    param(
        [string]$TempPath = $env:TEMP,
        $Previous
    )

    $now = Get-Date

    # --- CPU -------------------------------------------------------------------
    $cpu = 0.0
    try {
        $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0)
    } catch {}

    # --- Memory ----------------------------------------------------------------
    $memTotalMB = 0; $memFreeMB = 0; $memUsedPct = 0
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $memTotalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
        $memFreeMB  = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
        if ($memTotalMB -gt 0) { $memUsedPct = [math]::Round(100 * ($memTotalMB - $memFreeMB) / $memTotalMB, 0) }
    } catch {}

    # --- Network (cumulative bytes across up interfaces) -----------------------
    $bytesTotal = 0
    try {
        $bytesTotal = (Get-NetAdapterStatistics -ErrorAction SilentlyContinue |
            Measure-Object -Property ReceivedBytes, SentBytes -Sum |
            Measure-Object -Property Sum -Sum).Sum
    } catch {}
    $netMbps = 0.0
    if ($Previous -and $Previous.RawNetBytes -gt 0 -and $bytesTotal -gt 0) {
        $seconds = ($now - $Previous.Timestamp).TotalSeconds
        if ($seconds -gt 0) {
            $deltaBytes = $bytesTotal - $Previous.RawNetBytes
            if ($deltaBytes -lt 0) { $deltaBytes = 0 }
            $netMbps = [math]::Round(($deltaBytes * 8) / 1MB / $seconds, 1)   # Megabits/sec
        }
    }

    # --- Temp folder space -----------------------------------------------------
    $tempFreeGB = 0; $tempTotalGB = 0
    try {
        $drive = (Get-Item -LiteralPath $TempPath).PSDrive
        if ($drive) {
            $tempFreeGB  = [math]::Round($drive.Free / 1GB, 1)
            $tempTotalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 1)
        }
    } catch {}

    [pscustomobject]@{
        Timestamp    = $now
        CpuPercent   = [double]$cpu
        MemUsedPct   = [double]$memUsedPct
        MemUsedMB    = [double]($memTotalMB - $memFreeMB)
        MemTotalMB   = [double]$memTotalMB
        NetMbps      = [double]$netMbps
        RawNetBytes  = [double]$bytesTotal
        TempFreeGB   = [double]$tempFreeGB
        TempTotalGB  = [double]$tempTotalGB
    }
}

#endregion

#region ------------------------------------------------------------ Free space & compression estimate

function Get-A4950SelectionStats {
    <#
    .SYNOPSIS Count files and folders and sum their size across the top-level selected items.
    .DESCRIPTION
        Runs independently of hashing/manifest generation, so file/folder counts
        and total size are available even when EmbedManifest is off (e.g. Quick
        Transfer) - used for the activity log summary, the transfer log header,
        and the on-screen completion message.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$SourcePath)
    $fileCount = 0; $folderCount = 0; $totalBytes = 0L
    foreach ($root in $SourcePath) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            $folderCount++   # the top-level folder itself
            try {
                $dirs = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
                $folderCount += $dirs.Count
            } catch {}
            try {
                $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
                $fileCount += $files.Count
                if ($files.Count -gt 0) {
                    $sum = ($files | Measure-Object -Property Length -Sum).Sum
                    if ($sum) { $totalBytes += [int64]$sum }
                }
            } catch {}
        } elseif (Test-Path -LiteralPath $root) {
            $fileCount++
            try { $totalBytes += [int64](Get-Item -LiteralPath $root -ErrorAction Stop).Length } catch {}
        }
    }
    [pscustomobject]@{ FileCount = $fileCount; FolderCount = $folderCount; TotalBytes = $totalBytes }
}

function Format-A4950Bytes {
    <#
    .SYNOPSIS Human-readable byte size, e.g. 1536000000 -> "1.43 GB".
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][double]$Bytes)
    if ($Bytes -lt 0) { return 'unknown' }
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0; $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt $units.Count - 1) { $v /= 1024; $i++ }
    "{0:N2} {1}" -f $v, $units[$i]
}

function Get-A4950PathSizeBytes {
    <#
    .SYNOPSIS Total size in bytes of a file, or recursively of a folder.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try { return [int64](Get-Item -LiteralPath $Path -ErrorAction Stop).Length } catch { return 0 }
    }
    try {
        $sum = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($sum.Sum) { return [int64]$sum.Sum } else { return 0 }
    } catch { return 0 }
}

function Get-A4950CompressionRatio {
    <#
    .SYNOPSIS Rough PLANNING estimate of compressed-size / original-size.
    .DESCRIPTION
        Actual compression is entirely data-dependent (already-compressed media
        such as JPEG/MP4/ZIP barely shrinks; plain text/office documents shrink
        a lot). This heuristic exists only to size a free-space check and
        suggest settings - it is not a guarantee of the real archive size.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0, 9)][int]$Level,
        [ValidateSet('7z', 'zip')][string]$Format = 'zip'
    )
    $table = @{ 0 = 1.00; 1 = 0.92; 2 = 0.87; 3 = 0.82; 4 = 0.75; 5 = 0.68; 6 = 0.62; 7 = 0.58; 8 = 0.55; 9 = 0.52 }
    $ratio = $table[$Level]
    if ($Format -eq '7z' -and $Level -gt 0) { $ratio *= 0.93 }   # 7z format typically edges out zip
    return [math]::Round($ratio, 3)
}

function Get-A4950FreeSpace {
    <#
    .SYNOPSIS Free/total space for a local folder or a UNC share destination.
    .DESCRIPTION
        Local paths use [System.IO.DriveInfo]. UNC paths (\\server\share\...)
        have no direct .NET API, so the Scripting.FileSystemObject COM object
        is used - it reports free space for a UNC share without needing a
        mapped drive letter.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $result = [pscustomobject]@{ Ok = $false; FreeBytes = -1L; TotalBytes = -1L; Error = '' }
    try {
        if ($Path -match '^[A-Za-z]:\\') {
            $qualifier = Split-Path -Qualifier $Path
            $di = [System.IO.DriveInfo]::new($qualifier)
            $result.FreeBytes  = [int64]$di.AvailableFreeSpace
            $result.TotalBytes = [int64]$di.TotalSize
            $result.Ok = $true
        } else {
            $probe = $Path
            if (-not (Test-Path -LiteralPath $probe)) { $probe = Split-Path -Parent $probe }
            $fso = New-Object -ComObject Scripting.FileSystemObject
            $driveName = $fso.GetDriveName($fso.GetAbsolutePathName($probe))
            $drv = $fso.GetDrive($driveName)
            $result.FreeBytes  = [int64]$drv.FreeSpace
            $result.TotalBytes = [int64]$drv.TotalSize
            $result.Ok = $true
        }
    } catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}

#endregion

#region ------------------------------------------------------------ Logging & utilities

function New-A4950CaseFolderName {
    <#
    .SYNOPSIS Sanitise a case number into a filesystem-safe name.
    .DESCRIPTION
        A trailing "." is a legal filename character but, left in place,
        collides with the "." that separates the archive extension - e.g. a
        case number typed as "CMS-A12345." would otherwise produce
        "CMS-A12345..zip" (double dot). Trimmed here, along with trailing
        spaces (Windows itself silently drops trailing dots/spaces from
        names, so this only removes characters that wouldn't survive anyway).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CaseNumber)
    $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
    $pattern = "[{0}]" -f [regex]::Escape($invalid)
    ($CaseNumber -replace $pattern, '_').Trim().TrimEnd('.', ' ')
}

function Test-A4950CaseNumber {
    <#
    .SYNOPSIS Validate a case number against the required prefix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CaseNumber,
        [string]$Prefix = 'CMS-A'
    )
    if ([string]::IsNullOrWhiteSpace($CaseNumber)) { return $false }
    if (-not $CaseNumber.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    # Require at least one character after the prefix.
    return $CaseNumber.Length -gt $Prefix.Length
}

function Test-A4950OpName {
    <#
    .SYNOPSIS Validate an operator name: non-empty and entirely UPPERCASE.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $t = $Name.Trim()
    if ($t -cne $t.ToUpper()) { return $false }     # any lowercase letter fails
    if ($t -notmatch '[A-Z0-9]') { return $false }  # must contain at least one letter/digit
    return $true
}

function Write-A4950Log {
    <#
    .SYNOPSIS Append a timestamped, levelled line to a log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'STEP')][string]$Level = 'INFO'
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.PadRight(5), $Message
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

#endregion

Export-ModuleMember -Function *
