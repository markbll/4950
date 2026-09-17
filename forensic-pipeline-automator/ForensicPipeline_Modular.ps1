<#
.SYNOPSIS
    Air-Gapped Forensic Pipeline Automator - multi-engine processing GUI.

.DESCRIPTION
    Watches a source folder of .ufd mobile-extraction collections and, for
    each case, duplicates the collection onto the target drive of every
    forensic engine you enable, then launches each engine against its own
    copy in parallel - so engines never contend for read I/O on a single
    disk (see the accompanying setup guide for the recommended drive
    topology).

    Supported engines (each can be individually enabled/disabled, and each
    gets its own target drive and executable path):
      - Cellebrite Physical Analyzer (PA10)
      - Magnet AXIOM Process
      - Autopsy (Sleuth Kit)
      - Oxygen Forensic Detective
      - X-Ways Forensics
      - MSAB XRY / XAMN

    The pipeline itself runs in a background job (Start-Job) so the WPF
    window never becomes "Not Responding"; a DispatcherTimer on the UI
    thread polls the job's output stream and mirrors every line into the
    on-screen log without blocking it.

    A pre-flight check refuses to start unless every drive backing an
    enabled engine reports at least 500 GB free.

.NOTES
    Requires: Windows PowerShell 5.1+ (or PowerShell 7 on Windows), with a
    licensed, locally-installed copy of whichever engines you enable.
    Designed for air-gapped use - it makes no network calls of its own.

    IMPORTANT - command-line automation varies wildly between these tools
    and between versions of the same tool. The argument templates shipped
    below are a starting point, NOT a verified guarantee:
      - PA10 / AXIOM Process: confirm the switches against the CLI
        reference for your installed build.
      - Autopsy: mainline Autopsy does not process a case via command-line
        flags on its desktop executable. Its real unattended pipeline is
        the multi-user "Automated Ingest" architecture (PostgreSQL + Solr)
        that watches an input folder. This script therefore treats Autopsy
        as "WatchFolder" mode: it copies the case into the folder you
        configure and does NOT invoke autopsy64.exe directly. Set that
        folder to your configured Automated Ingest input directory and
        configure Automated Ingest itself per Autopsy's own documentation
        before relying on this.
      - Oxygen Forensic Detective: unattended/batch processing is normally
        gated behind Oxygen's own Automation/SDK add-on. Confirm your
        license tier and the exact invocation before use.
      - X-Ways Forensics: automation is normally driven through X-Tensions
        or a refinement/scripting (.txt) file rather than simple flags.
        Confirm the correct invocation in the X-Ways manual for your
        version.
      - MSAB XRY / XAMN: unattended decode/processing of an extraction
        typically requires the licensed XRY/XAMN Automate add-on. Confirm
        your license includes it and check its own CLI reference.

    Every argument template and executable path is editable in the GUI
    before you click Initialize - nothing here should be trusted blind in
    casework.

    Run:  Right-click -> "Run with PowerShell", or:
          powershell -ExecutionPolicy Bypass -File .\ForensicPipeline_Modular.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ----------------------------------------------------------------------------
# 0. Engine registry - add/remove/edit supported forensic engines here.
#    Mode 'Process'     : launches Exe with an ArgumentTemplate via
#                         Start-Process and waits for it to exit.
#    Mode 'WatchFolder' : copies the case into Target (a folder the tool's
#                         own automated-ingest feature watches) and does NOT
#                         wait for it to finish - the tool picks it up on its
#                         own schedule, outside this pipeline's visibility.
# ----------------------------------------------------------------------------
function ConvertTo-XamlText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

$script:EngineDefinitions = @(
    [ordered]@{
        Key             = 'PA10'
        DisplayName     = 'Cellebrite Physical Analyzer (PA10)'
        Mode            = 'Process'
        DefaultExePath  = 'C:\Program Files\Cellebrite\Forensic\Inseyets Physical Analyzer\pas.exe'
        DefaultTarget   = 'E:\'
        ArgumentTemplate= '-open "{SOURCE}" -method Forensic -project "{OUTPUT}" -examine'
        Notes           = 'Confirm these switches against the CLI reference for your installed PA10 build.'
    },
    [ordered]@{
        Key             = 'AXIOM'
        DisplayName     = 'Magnet AXIOM Process'
        Mode            = 'Process'
        DefaultExePath  = 'C:\Program Files\Magnet Forensics\Magnet AXIOM\Magnet AXIOM Process\AxiomProcess.exe'
        DefaultTarget   = 'F:\'
        ArgumentTemplate= '/v "Mobile" /i "{SOURCE}" /o "{OUTPUT}" /g'
        Notes           = 'Confirm these switches against the CLI reference for your installed AXIOM build.'
    },
    [ordered]@{
        Key             = 'AUTOPSY'
        DisplayName     = 'Autopsy (Sleuth Kit)'
        Mode            = 'WatchFolder'
        DefaultExePath  = ''
        DefaultTarget   = 'G:\AutopsyAutoIngest\Input'
        ArgumentTemplate= ''
        Notes           = "Autopsy's real unattended pipeline is its multi-user Automated Ingest cluster (PostgreSQL + Solr), which watches an input folder rather than accepting exe command-line flags. Point Target at that watched input folder - this tool only copies the case there; it does not launch Autopsy directly. Configure Automated Ingest per Autopsy's documentation first."
    },
    [ordered]@{
        Key             = 'OXYGEN'
        DisplayName     = 'Oxygen Forensic Detective'
        Mode            = 'Process'
        DefaultExePath  = 'C:\Program Files\Oxygen Forensic Detective\OxygenForensicDetective.exe'
        DefaultTarget   = 'H:\'
        ArgumentTemplate= '/import "{SOURCE}" /case "{OUTPUT}"'
        Notes           = "Unattended/batch processing is normally gated behind Oxygen's own Automation/SDK add-on - confirm your license tier and the exact switches before use."
    },
    [ordered]@{
        Key             = 'XWAYS'
        DisplayName     = 'X-Ways Forensics'
        Mode            = 'Process'
        DefaultExePath  = 'C:\Program Files\X-Ways Forensics\WinHex64.exe'
        DefaultTarget   = 'I:\'
        ArgumentTemplate= '"{SOURCE}" /A0'
        Notes           = 'X-Ways automation is normally driven through X-Tensions or a refinement/scripting (.txt) file rather than simple flags - confirm the correct invocation in the X-Ways manual for your version.'
    },
    [ordered]@{
        Key             = 'XRY'
        DisplayName     = 'MSAB XRY / XAMN'
        Mode            = 'Process'
        DefaultExePath  = 'C:\Program Files\MSAB\XAMN\XAMN.exe'
        DefaultTarget   = 'J:\'
        ArgumentTemplate= '-open "{SOURCE}" -export "{OUTPUT}"'
        Notes           = 'Unattended decode of an extraction typically requires the licensed XRY/XAMN Automate add-on - confirm your license includes it and check its own CLI reference before use.'
    }
)

function New-EngineRowXaml {
    param($Engine)
    $targetLabel = if ($Engine.Mode -eq 'WatchFolder') { 'Watched Ingest Folder:' } else { 'Target Drive/Folder:' }
    $exeLabel    = if ($Engine.Mode -eq 'WatchFolder') { 'Executable Path (unused - WatchFolder mode):' } else { 'Executable Path:' }
    $display     = ConvertTo-XamlText $Engine.DisplayName
    $target      = ConvertTo-XamlText $Engine.DefaultTarget
    $exe         = ConvertTo-XamlText $Engine.DefaultExePath
    $notes       = ConvertTo-XamlText $Engine.Notes
    $key         = $Engine.Key
@"
        <Border BorderBrush="#DDDDDD" BorderThickness="0,0,0,1" Padding="0,6,0,10" Margin="0,0,0,4">
          <StackPanel>
            <CheckBox Name="$($key)_Chk" Content="Enable: $display" FontWeight="Bold"/>
            <Grid Margin="20,4,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="230"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="70"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="26"/>
                <RowDefinition Height="26"/>
              </Grid.RowDefinitions>
              <Label Content="$targetLabel" Grid.Row="0" Grid.Column="0" Padding="0" VerticalAlignment="Center" FontSize="11"/>
              <TextBox Name="$($key)_TxtTarget" Text="$target" Grid.Row="0" Grid.Column="1" Height="22" VerticalAlignment="Center"/>
              <Button Name="$($key)_BtnTarget" Content="Browse" Grid.Row="0" Grid.Column="2" Height="22" Margin="5,0,0,0"/>
              <Label Content="$exeLabel" Grid.Row="1" Grid.Column="0" Padding="0" VerticalAlignment="Center" FontSize="11"/>
              <TextBox Name="$($key)_TxtExe" Text="$exe" Grid.Row="1" Grid.Column="1" Height="22" VerticalAlignment="Center"/>
              <Button Name="$($key)_BtnExe" Content="Browse" Grid.Row="1" Grid.Column="2" Height="22" Margin="5,0,0,0"/>
            </Grid>
            <TextBlock Text="$notes" FontSize="10" Foreground="#888888" TextWrapping="Wrap" Margin="20,3,0,0"/>
          </StackPanel>
        </Border>
"@
}

$EngineRowsXaml = ($script:EngineDefinitions | ForEach-Object { New-EngineRowXaml $_ }) -join "`n"

# ----------------------------------------------------------------------------
# 1. WPF graphical interface layout (XAML)
# ----------------------------------------------------------------------------
$XamlTemplate = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Air-Gapped Forensic Pipeline Automator" Height="800" Width="760" Background="#F4F4F4">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="260"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Source collection -->
        <GroupBox Header=" Source Collection " Grid.Row="0" Margin="0,0,0,10" Padding="10" FontWeight="Bold">
            <Grid FontWeight="Normal">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="160"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="80"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="32"/>
                </Grid.RowDefinitions>
                <Label Content="Source Folder (.ufd):" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox Name="TxtSrc" Grid.Row="0" Grid.Column="1" Height="23" VerticalAlignment="Center"/>
                <Button Name="BtnBrowseSrc" Content="Browse" Grid.Row="0" Grid.Column="2" Height="23" Margin="5,0,0,0"/>
            </Grid>
        </GroupBox>

        <!-- Forensic engines -->
        <GroupBox Header=" Forensic Engines (enable one or more; each engine's drive needs 500 GB+ free) " Grid.Row="1" Margin="0,0,0,10" Padding="10" FontWeight="Bold">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel FontWeight="Normal">
__ENGINE_ROWS__
                </StackPanel>
            </ScrollViewer>
        </GroupBox>

        <!-- Dynamic Real-Time Status Console -->
        <GroupBox Header=" Terminal Execution Log " Grid.Row="2" Margin="0,0,0,10" FontWeight="Bold">
            <TextBox Name="TxtLog" IsReadOnly="True" Background="#121212" Foreground="#00FF33"
                     FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" TextWrapping="Wrap" FontWeight="Normal"/>
        </GroupBox>

        <!-- Control Action Panel -->
        <Grid Grid.Row="3">
            <Label Name="LblDiskStatus" Content="System Idle - Ready for pre-flight disk check" Foreground="#555555" VerticalAlignment="Center" HorizontalAlignment="Left"/>
            <Button Name="BtnLaunch" Content="Initialize Pipeline" Height="35" HorizontalAlignment="Right" Width="200" FontWeight="Bold"/>
        </Grid>
    </Grid>
</Window>
"@

[xml]$XAML = $XamlTemplate.Replace('__ENGINE_ROWS__', $EngineRowsXaml)

# ----------------------------------------------------------------------------
# 2. Compile and initialize the WPF window instance
# ----------------------------------------------------------------------------
$Reader = New-Object System.Xml.XmlNodeReader $XAML
$Form   = [Windows.Markup.XamlReader]::Load($Reader)

$TxtSrc        = $Form.FindName("TxtSrc")
$TxtLog        = $Form.FindName("TxtLog")
$BtnLaunch     = $Form.FindName("BtnLaunch")
$LblDiskStatus = $Form.FindName("LblDiskStatus")

function Get-LocalFolder {
    param([string]$Description)
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = $Description
    if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $FolderBrowser.SelectedPath }
    return ""
}

$Form.FindName("BtnBrowseSrc").Add_Click({ $path = Get-LocalFolder "Select Pristine Extraction Source Directory"; if ($path) { $TxtSrc.Text = $path } })

# Wire each engine's controls (checkbox + target/exe textboxes + browse buttons).
foreach ($eng in $script:EngineDefinitions) {
    $eng.CtrlChk    = $Form.FindName("$($eng.Key)_Chk")
    $eng.CtrlTarget = $Form.FindName("$($eng.Key)_TxtTarget")
    $eng.CtrlExe    = $Form.FindName("$($eng.Key)_TxtExe")
    $btnTarget      = $Form.FindName("$($eng.Key)_BtnTarget")
    $btnExe         = $Form.FindName("$($eng.Key)_BtnExe")
    $capturedEngine = $eng

    $btnTarget.Add_Click({
        $path = Get-LocalFolder "Select target drive/folder for $($capturedEngine.DisplayName)"
        if ($path) { $capturedEngine.CtrlTarget.Text = $path }
    }.GetNewClosure())

    $btnExe.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = "Locate executable for $($capturedEngine.DisplayName)"
        $dlg.Filter = 'Executables (*.exe)|*.exe|All files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $capturedEngine.CtrlExe.Text = $dlg.FileName }
    }.GetNewClosure())

    if ($eng.Mode -eq 'WatchFolder') { $eng.CtrlExe.IsEnabled = $false; $btnExe.IsEnabled = $false }
}

function Write-PipelineConsole {
    param([string]$Message)
    $Form.Dispatcher.Invoke([Action]{
        $TxtLog.AppendText("[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message`r`n")
        $TxtLog.ScrollToEnd()
    })
}

# ----------------------------------------------------------------------------
# 3. Asynchronous pipeline logic
# ----------------------------------------------------------------------------
$script:PipelineJob   = $null
$script:PipelineTimer = $null

function Stop-PipelineTimer {
    if ($script:PipelineTimer) {
        $script:PipelineTimer.Stop()
        $script:PipelineTimer = $null
    }
}

$BtnLaunch.Add_Click({
    if ($script:PipelineJob) {
        [System.Windows.MessageBox]::Show("A pipeline run is already in progress. Wait for it to finish before starting another.", "Busy", "OK", "Warning") | Out-Null
        return
    }

    $Src = $TxtSrc.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Src)) {
        [System.Windows.MessageBox]::Show("Configuration Error: a source folder must be specified.", "Path Validation Error", "OK", "Error") | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $Src)) {
        [System.Windows.MessageBox]::Show("Source folder not found:`n$Src", "Path Validation Error", "OK", "Error") | Out-Null
        return
    }

    $selected = @($script:EngineDefinitions | Where-Object { $_.CtrlChk.IsChecked })
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Select at least one forensic engine to run.", "No Engine Selected", "OK", "Error") | Out-Null
        return
    }

    # Snapshot the enabled engines into plain data - Start-Job runs in a
    # separate process/runspace and cannot see WPF control objects.
    $engineConfigs = New-Object System.Collections.Generic.List[object]
    foreach ($eng in $selected) {
        $target = $eng.CtrlTarget.Text.Trim()
        $exe    = $eng.CtrlExe.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($target)) {
            [System.Windows.MessageBox]::Show("$($eng.DisplayName): a target drive/folder is required.", "Path Validation Error", "OK", "Error") | Out-Null
            return
        }
        if ($eng.Mode -eq 'Process' -and [string]::IsNullOrWhiteSpace($exe)) {
            [System.Windows.MessageBox]::Show("$($eng.DisplayName): an executable path is required.", "Path Validation Error", "OK", "Error") | Out-Null
            return
        }
        if (-not (Test-Path -LiteralPath $target)) {
            try { $null = New-Item -ItemType Directory -Path $target -Force }
            catch {
                [System.Windows.MessageBox]::Show("Could not create/access target folder for $($eng.DisplayName):`n$target`n$($_.Exception.Message)", "Path Validation Error", "OK", "Error") | Out-Null
                return
            }
        }

        $engineConfigs.Add([pscustomobject]@{
            Key             = $eng.Key
            DisplayName     = $eng.DisplayName
            Mode            = $eng.Mode
            Target          = $target
            Exe             = $exe
            ArgumentTemplate= $eng.ArgumentTemplate
        })
    }

    $TxtLog.Clear()
    $LblDiskStatus.Content    = "Pre-flight verification running..."
    $LblDiskStatus.Foreground = '#555555'
    $BtnLaunch.IsEnabled      = $false
    Write-PipelineConsole "[+] Pre-flight verification initiated. Processing drive matrix configurations for $($engineConfigs.Count) engine(s): $(($engineConfigs.DisplayName) -join ', ')."

    $script:PipelineJob = Start-Job -Name 'ForensicPipeline' -ScriptBlock {
        param($Src, $EngineConfigs)

        $ErrorActionPreference = 'Stop'
        $MinSpaceBytes = 500GB
        # The source drive is expected to be a read-only pristine repository
        # (see the setup guide), so the run log lives on the first enabled
        # engine's target instead - already confirmed writable below.
        $LogFile = Join-Path $EngineConfigs[0].Target 'ForensicPipeline_RunLog.txt'

        function Write-ToLocalLog {
            param([string]$Text)
            try { "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text | Out-File -FilePath $LogFile -Append -Encoding utf8 }
            catch { }
        }

        function Send-Msg {
            param([string]$Text)
            Write-ToLocalLog $Text
            Write-Output $Text
        }

        function Get-DriveInfo {
            param([string]$Path)
            $qualifier = Split-Path -Qualifier $Path -ErrorAction SilentlyContinue
            if (-not $qualifier) { return $null }
            return Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$qualifier'" -ErrorAction SilentlyContinue
        }

        # Validate executables for engines that are actually launched as a process.
        $missingExe = @($EngineConfigs | Where-Object { $_.Mode -eq 'Process' -and -not (Test-Path -LiteralPath $_.Exe) })
        if ($missingExe.Count -gt 0) {
            foreach ($m in $missingExe) { Send-Msg "[!] CRITICAL ERROR: $($m.DisplayName) executable not found at '$($m.Exe)'. Verify the software installation path." }
            return
        }

        # Offline disk capacity check - dedupe by drive letter so engines sharing a drive are checked once.
        $driveMap = @{}
        foreach ($e in $EngineConfigs) {
            $disk = Get-DriveInfo $e.Target
            if (-not $disk) {
                Send-Msg "[!] CRITICAL ERROR: Could not resolve a drive letter for $($e.DisplayName)'s target '$($e.Target)'. Use a local path such as E:\Cases, not a UNC share."
                return
            }
            $driveMap[$disk.DeviceID] = $disk
        }
        $shortOnSpace = @($driveMap.Values | Where-Object { $_.FreeSpace -lt $MinSpaceBytes })
        if ($shortOnSpace.Count -gt 0) {
            foreach ($d in $shortOnSpace) { Send-Msg ("[!] CRITICAL CAPACITY ERROR: Drive {0} has only {1:N1} GB free - minimum 500 GB required." -f $d.DeviceID, ($d.FreeSpace / 1GB)) }
            return
        }
        foreach ($d in $driveMap.Values) { Send-Msg ("[OK] Disk capacity confirmed - {0} : {1:N1} GB free." -f $d.DeviceID, ($d.FreeSpace / 1GB)) }

        $UfdFiles = Get-ChildItem -LiteralPath $Src -Filter '*.ufd' -ErrorAction SilentlyContinue
        if (-not $UfdFiles -or @($UfdFiles).Count -eq 0) {
            Send-Msg "[!] Pipeline halted: zero (.ufd) metadata collections found in '$Src'."
            return
        }

        Send-Msg "[+] Workstation space confirmed. Processing $(@($UfdFiles).Count) mobile case(s) across $($EngineConfigs.Count) engine(s): $($EngineConfigs.DisplayName -join ', ')."

        $succeeded = 0
        $failed    = 0

        foreach ($File in $UfdFiles) {
            $CaseName = $File.BaseName
            Send-Msg ">>> Spawning $($EngineConfigs.Count) processing node(s) for case file: $CaseName <<<"

            try {
                $BinPath = [System.IO.Path]::ChangeExtension($File.FullName, '.bin')
                if (-not (Test-Path -LiteralPath $BinPath)) { $BinPath = [System.IO.Path]::ChangeExtension($File.FullName, '.tar') }
                $hasSidecar = Test-Path -LiteralPath $BinPath
                if (-not $hasSidecar) { Send-Msg "[~] No sidecar .bin/.tar payload found alongside '$($File.Name)' - continuing with the .ufd metadata only." }

                $running = New-Object System.Collections.Generic.List[object]
                $caseOk  = $true

                foreach ($eng in $EngineConfigs) {
                    $workDir = Join-Path $eng.Target "$($CaseName)_$($eng.Key)_Run"
                    $null = New-Item -ItemType Directory -Path $workDir -Force

                    Send-Msg "[->] $($eng.DisplayName): duplicating forensic collection data to '$workDir'"
                    Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $workDir $File.Name) -Force
                    if ($hasSidecar) {
                        $binName = Split-Path $BinPath -Leaf
                        Copy-Item -LiteralPath $BinPath -Destination (Join-Path $workDir $binName) -Force
                    }

                    if ($eng.Mode -eq 'WatchFolder') {
                        Send-Msg "[Q] $($eng.DisplayName): case copied to its watched automated-ingest folder - it will be picked up on that tool's own schedule and is not tracked by this pipeline."
                        continue
                    }

                    $targetFile = Join-Path $workDir $File.Name
                    $outputDir  = Join-Path $workDir "$($eng.Key)_Decoded_Case"
                    $argString  = $eng.ArgumentTemplate.Replace('{SOURCE}', $targetFile).Replace('{OUTPUT}', $outputDir).Replace('{CASE}', $CaseName)

                    Send-Msg "[*] $($eng.DisplayName): launching headless engine instance..."
                    $proc = Start-Process -FilePath $eng.Exe -ArgumentList $argString -NoNewWindow -PassThru
                    $running.Add([pscustomobject]@{ Engine = $eng; Process = $proc })
                }

                $elapsedSeconds = 0
                while (@($running | Where-Object { -not $_.Process.HasExited }).Count -gt 0) {
                    Start-Sleep -Seconds 5
                    $elapsedSeconds += 5
                    if ($elapsedSeconds % 60 -eq 0) {
                        $states = $running | ForEach-Object { "$($_.Engine.DisplayName): $(if ($_.Process.HasExited) { 'done' } else { 'running' })" }
                        Send-Msg ("[...] $CaseName - {0} min elapsed. {1}" -f [int]($elapsedSeconds / 60), ($states -join ' | '))
                    }
                }

                foreach ($r in $running) {
                    $exitCode = $r.Process.ExitCode
                    if ($exitCode -eq 0) { Send-Msg "[OK] $($r.Engine.DisplayName) completed case '$CaseName' (exit code 0)." }
                    else {
                        Send-Msg "[!] $($r.Engine.DisplayName) exited with code $exitCode for case '$CaseName' - review its own case log."
                        $caseOk = $false
                    }
                }

                if ($caseOk) { $succeeded++ } else { $failed++ }
            }
            catch {
                $failed++
                Send-Msg "[!] ERROR processing case '$CaseName': $($_.Exception.Message)"
            }
        }

        Send-Msg "[=] Pipeline finished. $succeeded case(s) fully processed, $failed case(s) with errors (WatchFolder engines are queued only, not verified - check each tool directly). Run log: $LogFile"
    } -ArgumentList $Src, $engineConfigs

    # Poll the background job's output on a UI timer so the window never blocks.
    $script:PipelineTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PipelineTimer.Interval = [TimeSpan]::FromMilliseconds(750)
    $script:PipelineTimer.Add_Tick({
        $job = $script:PipelineJob
        if (-not $job) { Stop-PipelineTimer; return }

        Receive-Job -Job $job 2>&1 | ForEach-Object { Write-PipelineConsole $_ }

        if ($job.State -in @('Completed', 'Failed', 'Stopped')) {
            Receive-Job -Job $job 2>&1 | ForEach-Object { Write-PipelineConsole $_ }
            if ($job.State -eq 'Failed') {
                $reason = $job.ChildJobs[0].JobStateInfo.Reason
                $reasonText = if ($reason) { $reason.Message } else { 'Unknown error' }
                Write-PipelineConsole "[!] Pipeline job terminated unexpectedly: $reasonText"
                $LblDiskStatus.Content    = "Pipeline failed - see log"
                $LblDiskStatus.Foreground = '#B00020'
            } else {
                $LblDiskStatus.Content    = "Pipeline finished - see log for per-case results"
                $LblDiskStatus.Foreground = '#2E7D32'
            }
            Remove-Job -Job $job -Force
            $script:PipelineJob = $null
            $BtnLaunch.IsEnabled = $true
            Stop-PipelineTimer
        }
    })
    $script:PipelineTimer.Start()
})

$Form.Add_Closing({
    Stop-PipelineTimer
    if ($script:PipelineJob) { Remove-Job -Job $script:PipelineJob -Force -ErrorAction SilentlyContinue }
})

[void]$Form.ShowDialog()
