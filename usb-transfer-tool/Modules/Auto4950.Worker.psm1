<#
.SYNOPSIS
    Auto 49/50 - USB Transfer - background pipeline worker.

.DESCRIPTION
    Runs the full capture pipeline off the UI thread. All selected folders/
    files are hashed into one manifest and compressed into a SINGLE combined
    archive; a producer/consumer pipeline then transfers that archive (or its
    volumes, if split) while the consumer runspace handles hashing/verification.

    Communication with the GUI happens through a synchronized hashtable ($Shared):
        $Shared.Messages : System.Collections.Queue (synchronized)  - log/progress events
        $Shared.Cancel   : [bool]                                   - cooperative cancel flag
        $Shared.Running  : [bool]                                   - set false when finished

    The GUI drains $Shared.Messages on a DispatcherTimer and updates the UI.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Send-A4950Event {
    <#
    .SYNOPSIS Enqueue a structured event for the GUI to consume.
    #>
    param(
        [Parameter(Mandatory)] $Shared,
        [Parameter(Mandatory)][string]$Type,   # log | progress | status | stat | done
        [hashtable]$Data = @{}
    )
    $evt = @{ Type = $Type; Time = (Get-Date) } + $Data
    $Shared.Messages.Enqueue($evt)
}

function Write-A4950WorkerLog {
    param(
        [Parameter(Mandatory)] $Shared,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'STEP')][string]$Level = 'INFO'
    )
    Send-A4950Event -Shared $Shared -Type 'log' -Data @{ Level = $Level; Text = $Message }
    if ($Shared.LogFile) {
        try { Write-A4950Log -Path $Shared.LogFile -Message $Message -Level $Level } catch {}
    }
}

function Invoke-A4950TransferJob {
    <#
    .SYNOPSIS Execute the compress -> hash -> transfer -> verify pipeline.
    .PARAMETER Shared
        Synchronized hashtable carrying config, job parameters and the message queue.
        Required keys: Config, CaseNumber, DriveRoot, Items (string[] top-level paths),
        Messages (Queue), Cancel (bool), LogFile (string).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Shared)

    $cfg        = $Shared.Config
    $case       = $Shared.CaseNumber
    $caseSafe   = New-A4950CaseFolderName -CaseNumber $case
    $items      = @($Shared.Items)
    $sevenZip   = Resolve-SevenZip -PreferredPath $cfg.SevenZipPath
    $staging    = Join-Path (Expand-A4950Path $cfg.StagingFolder) $caseSafe
    # Destination is FLAT - no per-case sub-folder. Every job's files land
    # directly in NetworkShare, so the archive/manifest/log NAMES themselves
    # (uniqueBase below) are what keeps different jobs from colliding there,
    # not folder isolation.
    $destFolder = $cfg.NetworkShare

    # Cancel probe reused by 7-Zip and robocopy so both can be killed instantly.
    $cancel = ({ [bool]$Shared.Cancel }).GetNewClosure()
    # Job-wide stamp: also de-dupes a destination name that already exists.
    $Shared.Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    # CMS case and/or OP name, plus pass number if given (Get-TransferName
    # already built $case from whichever of those were supplied), plus this
    # job's timestamp - used for every file name that reaches the flat
    # destination, so two jobs never produce the same file name there.
    $uniqueBase = "${caseSafe}_$($Shared.Stamp)"

    try {
        Write-A4950WorkerLog $Shared "=== Job started for $case ===" 'STEP'
        Write-A4950WorkerLog $Shared "7-Zip      : $sevenZip"
        Write-A4950WorkerLog $Shared "Staging    : $staging"
        Write-A4950WorkerLog $Shared "Destination: $destFolder"
        Write-A4950WorkerLog $Shared "Items      : $($items.Count) top-level selection(s)"

        if (-not $sevenZip) { throw '7-Zip executable not found. Aborting.' }
        if (-not (Test-Path -LiteralPath $staging)) { New-Item -ItemType Directory -Path $staging -Force | Out-Null }

        # Thread-safe queue of archives ready to transfer + a bag of results.
        $transferQueue  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $producerDone   = [ref]$false
        $consumerResult = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

        # ---------------------------------------------------------------------
        # Consumer runspace: hashes + transfers each archive as it appears.
        # ---------------------------------------------------------------------
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $consumerRs = [runspacefactory]::CreateRunspace($iss)
        $consumerRs.ApartmentState = 'MTA'
        $consumerRs.Open()
        $consumerPs = [powershell]::Create()
        $consumerPs.Runspace = $consumerRs

        [void]$consumerPs.AddScript({
            param($Shared, $Queue, $ProducerDone, $DestFolder, $CoreModule, $WorkerModule, $ResultBag)
            Import-Module $CoreModule -Force
            Import-Module $WorkerModule -Force
            $cfg = $Shared.Config
            $cancel = ({ [bool]$Shared.Cancel }).GetNewClosure()
            while ($true) {
                if ($Shared.Cancel) { break }
                $archive = $null
                if ($Queue.TryDequeue([ref]$archive)) {
                  try {
                    $name = Split-Path -Leaf $archive
                    $size = 0; try { $size = (Get-Item -LiteralPath $archive).Length } catch {}
                    # Only hash the archive when integrity is actually wanted (verify or manifest).
                    # In Quick Transfer both are off, so NO hashing is performed here.
                    $srcSha = ''
                    if ($cfg.VerifyAfterTransfer -or $cfg.EmbedManifest) {
                        try { $srcSha = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash } catch {}
                    }
                    Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='xfer'; Action='start'; Name=$name }
                    Write-A4950WorkerLog $Shared "Transferring: $name" 'STEP'
                    $t = Copy-A4950ToShare -SourceFile $archive -DestinationFolder $DestFolder -TimeStamp $Shared.Stamp -CancelCheck $cancel
                    if ($t.Cancelled) {
                        Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='xfer'; Action='done'; Name=$name; Ok=$false }
                        break
                    }
                    $destName = if ($t.Destination) { Split-Path -Leaf $t.Destination } else { $name }
                    if ($t.Renamed) { Write-A4950WorkerLog $Shared "Name clash at destination - saved as: $destName" 'WARN' }
                    if (-not $t.Success -and $t.Error) { Write-A4950WorkerLog $Shared "Transfer error for $name : $($t.Error)" 'ERROR' }
                    if ($t.Success) {
                        $whenUtc = [DateTime]::UtcNow.ToString('o')
                        $shaText = if ($srcSha) { "SHA256=$srcSha" } else { 'SHA256=(not calculated - quick transfer)' }
                        Write-A4950WorkerLog $Shared "Transferred: $destName  $shaText  ($whenUtc)" 'OK'
                        # "Confirmed transferred" = copy succeeded AND, if verification was
                        # requested, the destination hash actually matches.
                        $confirmed = $true
                        if ($cfg.VerifyAfterTransfer) {
                            $d = ''; try { $d = (Get-FileHash -LiteralPath $t.Destination -Algorithm SHA256).Hash } catch {}
                            if ($d -eq $srcSha -and $srcSha) { Write-A4950WorkerLog $Shared "Verified   : $destName (SHA-256 match)" 'OK' }
                            else { Write-A4950WorkerLog $Shared "VERIFY FAIL: $destName (SHA-256 mismatch)" 'ERROR'; $confirmed = $false }
                        }
                        # Local copies are always kept in staging now, regardless of
                        # outcome - they're only removed via the operator-confirmed
                        # "Delete Local Copies" button once the destination is verified
                        # by eye (or manually, from the staging folder).
                        $ResultBag.Add([pscustomobject]@{ Name=$destName; Sha256=$srcSha; SizeBytes=$size; TransferredUtc=$whenUtc; Transferred=$confirmed })
                        Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='xfer'; Action='done'; Name=$name; Ok=$confirmed }
                    } else {
                        Write-A4950WorkerLog $Shared "TRANSFER FAIL: $name (exit $($t.ExitCode))" 'ERROR'
                        $ResultBag.Add([pscustomobject]@{ Name=$name; Sha256=$srcSha; SizeBytes=$size; TransferredUtc=''; Transferred=$false })
                        Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='xfer'; Action='done'; Name=$name; Ok=$false }
                    }
                  }
                  catch {
                    # Fault handling: keep the transfer loop alive on a per-file error.
                    Write-A4950WorkerLog $Shared "ERROR transferring '$archive': $($_.Exception.Message)" 'ERROR'
                  }
                } elseif ($ProducerDone.Value) {
                    break   # nothing left and producer finished
                } else {
                    Start-Sleep -Milliseconds 150
                }
            }
        })
        [void]$consumerPs.AddArgument($Shared)
        [void]$consumerPs.AddArgument($transferQueue)
        [void]$consumerPs.AddArgument($producerDone)
        [void]$consumerPs.AddArgument($destFolder)
        [void]$consumerPs.AddArgument($Shared.CoreModule)
        [void]$consumerPs.AddArgument($Shared.WorkerModule)
        [void]$consumerPs.AddArgument($consumerResult)
        $consumerHandle = $consumerPs.BeginInvoke()

        # ---------------------------------------------------------------------
        # Producer: hash + compress the ENTIRE selection into ONE combined
        # archive (always - this is not configurable), then enqueue it/its
        # volumes for transfer.
        # ---------------------------------------------------------------------
        $volMB = 0
        try { $volMB = [int]$cfg.VolumeSizeMB } catch {}

        $existingItems = @()
        foreach ($it in $items) {
            if (Test-Path -LiteralPath $it) { $existingItems += $it }
            else { Write-A4950WorkerLog $Shared "SKIP (missing): $it" 'WARN' }
        }
        if (-not $Shared.Cancel -and $existingItems.Count -gt 0) {
          try {
            Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage = 'item'; Current = 1; Total = 1; Name = "$($existingItems.Count) combined item(s)" }
            Write-A4950WorkerLog $Shared "--- Combining $($existingItems.Count) selected item(s) into one archive ---" 'STEP'

            # 1) Hash ALL originals -> one manifest covering every selected item
            $manifestPath = Join-Path $staging ("{0}_MANIFEST.txt" -f $uniqueBase)
            $extraFiles = @()
            if ($cfg.EmbedManifest) {
                Write-A4950WorkerLog $Shared "Hashing originals ($($cfg.HashAlgorithms -join ', '))..."
                $m = New-A4950Manifest -SourcePath $existingItems -ManifestPath $manifestPath -CaseNumber $case `
                        -Algorithms $cfg.HashAlgorithms `
                        -OnProgress ({
                            param($c, $t, $f)
                            if ($Shared.Cancel) { return }
                            if ($t -gt 0 -and ($c % 25 -eq 0 -or $c -eq $t)) {
                                Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='hash'; Current=$c; Total=$t; Name=(Split-Path -Leaf $f) }
                            }
                        }.GetNewClosure())
                Write-A4950WorkerLog $Shared "Manifest   : $($m.FileCount) files hashed -> $(Split-Path -Leaf $manifestPath)" 'OK'
                $extraFiles = @($manifestPath, $m.CsvPath)
            }

            if (-not $Shared.Cancel) {
                # 2) Compress ALL items together into ONE archive. Split into volumes if configured.
                # TrimStart('.') on the format guards against a stray leading dot in
                # config (e.g. ".zip" instead of "zip") producing a double dot here.
                $archivePath = Join-Path $staging ("{0}.{1}" -f $uniqueBase, $cfg.ArchiveFormat.TrimStart('.'))
                $splitNote = if ($volMB -gt 0) { " split @ ${volMB} MB" } else { '' }
                Write-A4950WorkerLog $Shared "Compressing: $($existingItems.Count) item(s) -> $(Split-Path -Leaf $archivePath) (level $($cfg.CompressionLevel)$splitNote)" 'STEP'
                Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='compress'; Percent=-1; Name=$caseSafe }
                # -OnPartReady enqueues each produced file for transfer the moment it is
                # complete, so transfer starts ASAP rather than waiting for the whole
                # archive. EXCEPT .001: it's always held back and enqueued last, once
                # every other part is already queued (or, for an unsplit archive,
                # there's nothing to hold it back from). This is deliberate: nothing at
                # the destination can be reassembled/opened until .001 itself lands, so
                # holding it back is a "not usable until everything else has arrived"
                # signal. For a zip split into volumes, we write/close .001, .002, ...
                # strictly in that order ourselves, so every part but .001 is still
                # queued the moment it's done. For 7z's own -v volumes, completion order
                # inside the running process isn't observable from outside it, so all of
                # those are only reported here as one batch, right after 7z.exe has fully
                # exited - .001 is simply queued last within that same batch.
                # [ref] rather than a plain variable: .GetNewClosure() snapshots plain
                # variables by VALUE (a mutation inside the closure would neither persist
                # across the multiple calls below nor be visible out here afterwards) - a
                # [ref] is itself a reference type, so mutating .Value is visible both
                # across repeated invocations and back in this outer scope.
                $heldFirstPart = [ref]$null
                $a = New-A4950Archive -SevenZipPath $sevenZip -SourcePath $existingItems -ArchivePath $archivePath `
                        -Level $cfg.CompressionLevel -Format $cfg.ArchiveFormat -VolumeSizeMB $volMB -Password $cfg.Password `
                        -ExcludePatterns $cfg.ExcludePatterns -ExtraFiles $extraFiles -CancelCheck $cancel `
                        -LowResource:([bool]$cfg.SlowMachineMode) `
                        -OnPartReady ({
                            param($p)
                            $leaf = Split-Path -Leaf $p
                            if ($leaf -match '\.001$' -and -not $heldFirstPart.Value) {
                                $heldFirstPart.Value = $p
                                Write-A4950WorkerLog $Shared "Holding back for last: $leaf (transfers once every other part is queued)" 'INFO'
                            } else {
                                $transferQueue.Enqueue($p)
                                Write-A4950WorkerLog $Shared "Queued for transfer: $leaf" 'INFO'
                            }
                        }.GetNewClosure())

                if ($a.Cancelled) {
                    Write-A4950WorkerLog $Shared "Compression cancelled: $caseSafe" 'WARN'
                } else {
                    if ($heldFirstPart.Value -and (Test-Path -LiteralPath $heldFirstPart.Value)) {
                        $transferQueue.Enqueue($heldFirstPart.Value)
                        Write-A4950WorkerLog $Shared "Queued for transfer (last): $(Split-Path -Leaf $heldFirstPart.Value)" 'INFO'
                    }
                    Send-A4950Event -Shared $Shared -Type 'progress' -Data @{ Stage='compress'; Percent=100; Name=$caseSafe }
                    if ($a.Success) {
                        $desc = if ($a.Files.Count -gt 1) { "$($a.Files.Count) volume(s)" } else { Split-Path -Leaf $a.Files[0] }
                        Write-A4950WorkerLog $Shared "Compressed : $($existingItems.Count) item(s) -> $desc" 'OK'
                    } else {
                        Write-A4950WorkerLog $Shared "COMPRESS FAIL: $caseSafe (exit $($a.ExitCode))" 'ERROR'
                    }
                }
            }
          }
          catch {
            Write-A4950WorkerLog $Shared "ERROR combining selected items: $($_.Exception.Message)" 'ERROR'
          }
        }

        # Signal producer completion and wait for the consumer to drain.
        $producerDone.Value = $true
        if (-not $Shared.Cancel) { Write-A4950WorkerLog $Shared 'All items compressed. Waiting for transfers to finish...' 'STEP' }
        try { $consumerPs.EndInvoke($consumerHandle) } catch {}
        $consumerPs.Dispose(); $consumerRs.Dispose()

        $records = @($consumerResult)
        $done    = @($records | Where-Object { $_.Transferred })
        $ok      = $done.Count
        $fail    = @($records | Where-Object { -not $_.Transferred }).Count
        $cancelled = [bool]$Shared.Cancel

        # ---------------------------------------------------------------------
        # Transfer log. On cancel/failure it is marked "FAILED TRANSFER".
        # ---------------------------------------------------------------------
        $logFileName = $null
        if ($ok -gt 0) {
            $isFailed = $cancelled -or ($fail -gt 0)
            $logName  = if ($isFailed) { "${uniqueBase}_FAILED_TRANSFER.log" } else { "${uniqueBase}_TRANSFER.log" }
            $logPath  = Join-Path $staging $logName
            try {
                Write-A4950TransferLog -LogPath $logPath -Records $done -Reference $case -Failed:$isFailed | Out-Null
                # Copy the log to the destination (no cancel check - always send it).
                $lt = Copy-A4950ToShare -SourceFile $logPath -DestinationFolder $destFolder -TimeStamp $Shared.Stamp
                if ($lt.Success) {
                    $logFileName = Split-Path -Leaf $lt.Destination
                    Write-A4950WorkerLog $Shared "Transfer log written and sent: $logFileName" ($(if ($isFailed) {'WARN'} else {'OK'}))
                }
            } catch { Write-A4950WorkerLog $Shared "Could not write/send transfer log: $($_.Exception.Message)" 'ERROR' }
        }

        # ---------------------------------------------------------------------
        # Cleanup staging: always on cancel (an aborted job's partial output
        # has no evidentiary value). On a completed job, local copies are
        # ALWAYS kept in $staging - they are only removed by the operator,
        # either manually or via the confirm-and-delete "Delete Local
        # Copies" button on the transfer-finished window, after they've
        # confirmed the files actually reached the destination.
        # ---------------------------------------------------------------------
        if ($cancelled) {
            try {
                Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
                Write-A4950WorkerLog $Shared "Cleaned up temp files: $staging" 'INFO'
            } catch {}
            Write-A4950WorkerLog $Shared "=== CANCELLED: $ok file(s) already transferred, temp cleaned ===" 'WARN'
        } else {
            if ($fail -gt 0) {
                Write-A4950WorkerLog $Shared "Temp files kept in $staging ($fail item(s) not confirmed - review before deleting)." 'WARN'
            } else {
                Write-A4950WorkerLog $Shared "Local copies kept in $staging - delete manually or via 'Delete Local Copies' once confirmed at the destination." 'INFO'
            }
            Write-A4950WorkerLog $Shared "=== Job complete: $ok transferred, $fail failed ===" ($(if ($fail) {'WARN'} else {'OK'}))
        }
        # Staging is included so the GUI's "Delete Local Copies" button knows
        # what to remove; omitted when cancelled since it's already gone above.
        $stagingForGui = if ($cancelled) { $null } else { $staging }
        # Every file actually written to the destination: the archive
        # volume(s)/single archive plus the transfer log copied alongside it.
        $filesForGui = @($done | ForEach-Object { $_.Name })
        if ($logFileName) { $filesForGui += $logFileName }
        Send-A4950Event -Shared $Shared -Type 'done' -Data @{ Ok = $ok; Fail = $fail; Cancelled = $cancelled; Destination = $destFolder; Staging = $stagingForGui; Files = $filesForGui }
    }
    catch {
        Write-A4950WorkerLog $Shared "FATAL: $($_.Exception.Message)" 'ERROR'
        Send-A4950Event -Shared $Shared -Type 'done' -Data @{ Ok = 0; Fail = 1; Error = $_.Exception.Message }
    }
    finally {
        $Shared.Running = $false
    }
}

Export-ModuleMember -Function *
