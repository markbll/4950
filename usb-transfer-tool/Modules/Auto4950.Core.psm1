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
        ArchiveFormat       = 'zip'                     # zip | 7z
        VolumeSizeMB        = 2048                      # Split archives into volumes of this size (MB). 0 = no split
        Password            = ''                       # Optional AES-256 archive password (blank = none)
        # --- Hashing -----------------------------------------------------------
        HashAlgorithms      = @('SHA256', 'MD5')       # Original-file hashing
        EmbedManifest       = $true                    # Include hash manifest inside each archive
        # --- Behaviour ---------------------------------------------------------
        AutoPromptOnInsert  = $true                    # Show the action prompt when a USB drive appears
        AutoTransfer        = $false                   # Start automatically on insert if a CMS case / OP name is set
        DefaultSelectAll    = $true                    # Pre-select all folders/files by default
        VerifyAfterTransfer = $true                    # Re-hash the archive at destination
        DeleteLocalArchive  = $true                    # Remove staged/temp files once confirmed transferred
        StagingFolder       = 'C:\temp'                # Where archives are staged before transfer
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
        process tree so the operation stops almost immediately.
        Returns @{ ExitCode; Cancelled; Output }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [scriptblock]$CancelCheck
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
        [scriptblock]$OnOutput
    )

    $archiveDir = Split-Path -Parent $ArchivePath
    if (-not (Test-Path -LiteralPath $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }
    $archiveLeaf = Split-Path -Leaf $ArchivePath
    # Split parts are named "<base>.001" (no format extension) - see splitting
    # code below - so stale-file matching is done against the extension-less
    # base name, which also still matches the whole archive itself.
    $baseLeaf = [System.IO.Path]::GetFileNameWithoutExtension($ArchivePath)

    # Remove any stale output from a previous run so volume detection is clean.
    Get-ChildItem -LiteralPath $archiveDir -Filter "$baseLeaf.*" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Build 7z argument list.  'a' = add, -mx = level, -t = type.
    # Multiple -SourcePath entries are added to the SAME archive in one pass,
    # so several selected folders/files end up combined into a single zip.
    #
    # NOTE: 7-Zip's -v (volumes) switch only splits the native 7z container -
    # it silently does NOT split zip archives (7z.exe just writes one whole
    # .zip and ignores -v). So for zip we build the complete archive here and
    # split it ourselves afterwards (see Split-A4950File below); for 7z we let
    # 7-Zip's own -v do it natively as before.
    $splitZipOurselves = ($Format -eq 'zip' -and $VolumeSizeMB -gt 0)
    $szArgs = [System.Collections.Generic.List[string]]::new()
    $szArgs.AddRange([string[]]@('a', "-t$Format", "-mx=$Level", '-y', $ArchivePath))
    foreach ($sp in $SourcePath) { $szArgs.Add($sp) }
    if ($Format -eq '7z') { $szArgs.Add('-mmt=on') }          # multi-threaded
    if ($VolumeSizeMB -gt 0 -and -not $splitZipOurselves) { $szArgs.Add("-v${VolumeSizeMB}m") }   # 7z native volumes
    if ($ExtraFiles)      { foreach ($ef in $ExtraFiles) { $szArgs.Add($ef) } }
    if ($Password) {
        $szArgs.Add("-p$Password")
        if ($Format -eq '7z') { $szArgs.Add('-mhe=on') }      # encrypt headers too
    }
    if ($ExcludePatterns) {
        foreach ($x in $ExcludePatterns) { $szArgs.Add("-xr!$x") }
    }

    $result = [pscustomobject]@{
        Success     = $false
        Cancelled   = $false
        ArchivePath = $ArchivePath
        Files       = @()               # actual output file(s): the archive, or its volume parts
        IsSplit     = ($VolumeSizeMB -gt 0)
        ExitCode    = -1
        Output      = ''
    }

    $run = Invoke-A4950Process -FilePath $SevenZipPath -Arguments $szArgs -CancelCheck $CancelCheck
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

    if ($splitZipOurselves) {
        # zip: 7-Zip wrote one complete file at $ArchivePath - split it ourselves
        # into .001/.002/... parts of the requested size, then remove the whole
        # file so only the parts remain (matching 7-Zip's own -v behaviour).
        # We read/write strictly in order (.001 fully closed before .002 starts),
        # so -OnPartReady fires per part in true completion order, letting the
        # caller start transferring .001 immediately rather than waiting for
        # the whole split to finish.
        if (Test-Path -LiteralPath $ArchivePath) {
            $split = Split-A4950File -Path $ArchivePath -ChunkBytes ([int64]$VolumeSizeMB * 1MB) `
                        -CancelCheck $CancelCheck -OnPartReady $OnPartReady
            if ($split.Cancelled) {
                $result.Cancelled = $true
                Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue
                Get-ChildItem -LiteralPath $archiveDir -Filter "$baseLeaf.*" -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                return $result
            }
            if ($split.Success -and $split.Parts.Count -gt 0) {
                Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue
                $result.Files = @($split.Parts)
            } else {
                $result.Files = @($ArchivePath)   # splitting failed - fall back to the whole file
                if ($OnPartReady) { & $OnPartReady $ArchivePath }
            }
        }
    }
    else {
        # 7z's own -v volumes (or an unsplit archive of either format) are only
        # known to exist, and only guaranteed complete, once 7z.exe has fully
        # exited - the process is a black box while running, and 7-Zip does not
        # necessarily finalise volumes in ascending numeric order internally
        # (e.g. the FIRST volume can be the LAST one it finishes writing), so
        # there is no safe way to start transferring any of its volumes early.
        # All produced files are reported via -OnPartReady together, in one
        # batch, only after the process has completed.
        if ($VolumeSizeMB -gt 0) {
            # With -v, 7-Zip writes <archive>.<format>.001, .002, ... (e.g.
            # "case.7z.001") - rename each volume to strip the format
            # extension so the on-disk name matches our own zip-splitting
            # convention: "case.001" instead of "case.7z.001".
            $vols = Get-ChildItem -LiteralPath $archiveDir -Filter "$archiveLeaf.*" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.\d{3}$' } | Sort-Object Name
            if ($vols) {
                $renamedPaths = foreach ($v in $vols) {
                    $suffix  = $v.Name.Substring($archiveLeaf.Length)   # e.g. ".001"
                    $newName = "$baseLeaf$suffix"
                    $newPath = Join-Path $archiveDir $newName
                    Rename-Item -LiteralPath $v.FullName -NewName $newName -Force
                    $newPath
                }
                $result.Files = @($renamedPaths)
            }
            elseif (Test-Path -LiteralPath $ArchivePath) { $result.Files = @($ArchivePath) }  # not actually split
        } else {
            if (Test-Path -LiteralPath $ArchivePath) { $result.Files = @($ArchivePath) }
        }
        if ($OnPartReady) { foreach ($f in $result.Files) { & $OnPartReady $f } }
    }

    # 7-Zip exit codes: 0 = OK, 1 = warning (still usable).
    $result.Success = ($result.ExitCode -in 0, 1) -and ($result.Files.Count -gt 0)
    return $result
}

function Split-A4950File {
    <#
    .SYNOPSIS Split a file into fixed-size .001, .002, ... parts (raw byte split).
    .DESCRIPTION
        Used for zip archives, since 7-Zip's -v volume switch does not support
        the zip container format (it silently produces one whole file instead).
        The parts are plain sequential byte chunks, named "<base>.001",
        "<base>.002", ... (the original file's extension is dropped, so a
        split of "archive.zip" produces "archive.001", "archive.002", ...) -
        reassemble by concatenating them in order, e.g. on Windows:
            copy /b archive.001+archive.002+archive.003 archive.zip
        This is the same mechanism 7-Zip's own volumes use internally, so the
        parts are handled identically by the rest of the pipeline (transfer,
        naming, "open the .001" instructions).

        We read and write strictly in order - .001 is opened, fully written and
        CLOSED before .002 is even created - so each part's completion is known
        exactly and in true numeric order. -OnPartReady is invoked with a part's
        full path immediately after it is closed (fully flushed to disk), so a
        caller can start transferring it right away instead of waiting for the
        whole file to be split. It is never called for a part that was still
        being written when cancellation happened.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int64]$ChunkBytes,
        [scriptblock]$CancelCheck,
        [scriptblock]$OnPartReady
    )
    $parts = New-Object System.Collections.Generic.List[string]
    # Cast both args to [int64] explicitly - PowerShell's overload resolution
    # can otherwise pick Math.Min(Int32,Int32) and fail converting a >2GB
    # ChunkBytes value into Int32 ("value was either too large or too small").
    $bufSize = [int][Math]::Min([int64]$ChunkBytes, [int64]4MB)
    $buffer = New-Object byte[] $bufSize
    $partIndex = 0
    $cancelled = $false
    # Parts drop the original extension, e.g. "archive.zip" -> "archive.001",
    # not "archive.zip.001".
    $baseNoExt = [System.IO.Path]::ChangeExtension($Path, $null)

    $in = [System.IO.File]::OpenRead($Path)
    try {
        while ($in.Position -lt $in.Length) {
            if ($CancelCheck -and (& $CancelCheck)) { $cancelled = $true; break }
            $partIndex++
            $partPath = "{0}.{1:D3}" -f $baseNoExt, $partIndex
            $partOk = $false
            $out = [System.IO.File]::OpenWrite($partPath)
            try {
                $remaining = $ChunkBytes
                while ($remaining -gt 0 -and $in.Position -lt $in.Length) {
                    if ($CancelCheck -and (& $CancelCheck)) { $cancelled = $true; break }
                    $toRead = [int][Math]::Min([int64]$buffer.Length, [int64]$remaining)
                    $n = $in.Read($buffer, 0, $toRead)
                    if ($n -le 0) { break }
                    $out.Write($buffer, 0, $n)
                    $remaining -= $n
                }
                if (-not $cancelled) { $partOk = $true }
            } finally { $out.Dispose() }   # fully flushed and closed at this point
            if ($cancelled) {
                Remove-Item -LiteralPath $partPath -Force -ErrorAction SilentlyContinue
                break
            }
            if ($partOk) {
                $parts.Add($partPath)
                if ($OnPartReady) { & $OnPartReady $partPath }   # safe: this part is complete and closed
            }
        }
    } finally { $in.Dispose() }

    if ($cancelled) {
        foreach ($p in $parts) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        return [pscustomobject]@{ Success = $false; Cancelled = $true; Parts = @() }
    }
    return [pscustomobject]@{ Success = $true; Cancelled = $false; Parts = @($parts) }
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
    $out = @{}
    foreach ($alg in $Algorithms) {
        try {
            $out[$alg] = (Get-FileHash -LiteralPath $Path -Algorithm $alg).Hash
        } catch {
            $out[$alg] = "ERROR: $($_.Exception.Message)"
        }
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
        if ($f.FullName.Length -gt $e.Root.Length -and $f.FullName.StartsWith($e.Root)) {
            $rel = $f.FullName.Substring($e.Root.Length).TrimStart('\', '/')
        }
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = $f.Name }
        if ($multi) { $rel = "$($e.Label)\$rel" }   # disambiguate across combined top-level items
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
            $rcArgs = @($srcDir, $DestinationFolder, $srcName, '/J', '/R:2', '/W:3', '/NP', '/NDL', '/NJH', '/NJS')
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
        [switch]$Failed
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
    [void]$sb.AppendLine("Generated UTC : $([DateTime]::UtcNow.ToString('o'))")
    [void]$sb.AppendLine("Machine       : $env:COMPUTERNAME")
    [void]$sb.AppendLine("Operator      : $env:USERNAME")
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

function Get-A4950SuggestedCompression {
    <#
    .SYNOPSIS Find the fastest format/level whose estimated size fits in the free space.
    .OUTPUTS $null if nothing fits, even at maximum (level 9, 7z) compression.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int64]$SourceBytes,
        [Parameter(Mandatory)][int64]$FreeBytes
    )
    foreach ($fmt in @('zip', '7z')) {
        for ($lvl = 0; $lvl -le 9; $lvl++) {
            $ratio = Get-A4950CompressionRatio -Level $lvl -Format $fmt
            $est = [int64]($SourceBytes * $ratio * 1.02)   # +2% archive/manifest overhead
            if ($est -lt $FreeBytes) {
                return [pscustomobject]@{ Level = $lvl; Format = $fmt; EstimatedBytes = $est }
            }
        }
    }
    return $null
}

#endregion

#region ------------------------------------------------------------ Logging & utilities

function New-A4950CaseFolderName {
    <#
    .SYNOPSIS Sanitise a case number into a filesystem-safe name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CaseNumber)
    $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
    $pattern = "[{0}]" -f [regex]::Escape($invalid)
    ($CaseNumber -replace $pattern, '_').Trim()
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
