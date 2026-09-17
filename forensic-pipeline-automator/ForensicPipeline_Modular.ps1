<#
.SYNOPSIS
    Air-Gapped Forensic Pipeline Automator - dual PA10 / AXIOM processing GUI.

.DESCRIPTION
    Watches a source folder of .ufd mobile-extraction collections and, for
    each case, duplicates the collection onto two separate high-speed NVMe
    "processing" drives and launches Cellebrite Physical Analyzer (PA10) and
    Magnet AXIOM Process against each copy in parallel - so the two engines
    never contend for read I/O on a single disk (see the accompanying setup
    guide for the recommended drive topology).

    The pipeline itself runs in a background job (Start-Job) so the WPF
    window never becomes "Not Responding"; a DispatcherTimer on the UI thread
    polls the job's output stream and mirrors every line into the on-screen
    log without blocking it.

    A pre-flight check refuses to start unless both target drives report at
    least 500 GB free.

.NOTES
    Requires: Windows PowerShell 5.1+ (or PowerShell 7 on Windows), with a
    licensed, locally-installed copy of Cellebrite Physical Analyzer (PA10)
    and Magnet AXIOM Process. Designed for air-gapped use - it makes no
    network calls of its own.

    Cellebrite and Magnet both change their command-line switches between
    releases, so the pas.exe / AxiomProcess.exe argument lists below are a
    starting point, not a guarantee - confirm them against the CLI reference
    shipped with your installed version before relying on this in casework.

    Run:  Right-click -> "Run with PowerShell", or:
          powershell -ExecutionPolicy Bypass -File .\ForensicPipeline_Modular.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ----------------------------------------------------------------------------
# 1. WPF graphical interface layout (XAML)
# ----------------------------------------------------------------------------
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Air-Gapped Forensic Pipeline Automator (PA10 &amp; Axiom)" Height="580" Width="680" Background="#F4F4F4">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Target Forensic Workspaces -->
        <GroupBox Header=" Pipeline Workspace Configurations (Target High-Speed NVMe Drives) " Grid.Row="0" Margin="0,0,0,10" Padding="10" FontWeight="Bold">
            <Grid FontWeight="Normal">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="160"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="80"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                </Grid.RowDefinitions>

                <Label Content="Source Folder (.ufd):" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox Name="TxtSrc" Grid.Row="0" Grid.Column="1" Height="23" VerticalAlignment="Center"/>
                <Button Name="BtnBrowseSrc" Content="Browse" Grid.Row="0" Grid.Column="2" Height="23" Margin="5,0,0,0"/>

                <Label Content="PA10 NVMe Drive (E:\):" Grid.Row="1" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox Name="TxtPaOut" Grid.Row="1" Grid.Column="1" Height="23" VerticalAlignment="Center"/>
                <Button Name="BtnBrowsePa" Content="Browse" Grid.Row="1" Grid.Column="2" Height="23" Margin="5,0,0,0"/>

                <Label Content="Axiom NVMe Drive (F:\):" Grid.Row="2" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox Name="TxtAxOut" Grid.Row="2" Grid.Column="1" Height="23" VerticalAlignment="Center"/>
                <Button Name="BtnBrowseAx" Content="Browse" Grid.Row="2" Grid.Column="2" Height="23" Margin="5,0,0,0"/>
            </Grid>
        </GroupBox>

        <!-- Static Air-Gapped Executable Toolpaths -->
        <GroupBox Header=" Static Tool Executable Paths " Grid.Row="1" Margin="0,0,0,10" Padding="10" FontWeight="Bold">
            <Grid FontWeight="Normal">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="160"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                </Grid.RowDefinitions>

                <Label Content="PA10 pas.exe Engine:" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox Name="TxtPaExe" Text="C:\Program Files\Cellebrite\Forensic\Inseyets Physical Analyzer\pas.exe" Grid.Row="0" Grid.Column="1" Height="23" VerticalAlignment="Center"/>

                <Label Content="Axiom Process Engine:" Grid.Row="1" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox Name="TxtAxExe" Text="C:\Program Files\Magnet Forensics\Magnet AXIOM\Magnet AXIOM Process\AxiomProcess.exe" Grid.Row="1" Grid.Column="1" Height="23" VerticalAlignment="Center"/>
            </Grid>
        </GroupBox>

        <!-- Dynamic Real-Time Status Console -->
        <GroupBox Header=" Terminal Execution Log " Grid.Row="2" Margin="0,0,0,10" FontWeight="Bold">
            <TextBox Name="TxtLog" IsReadOnly="True" Background="#121212" Foreground="#00FF33"
                     FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" TextWrapping="Wrap" FontWeight="Normal"/>
        </GroupBox>

        <!-- Control Action Panel -->
        <Grid Grid.Row="3">
            <Label Name="LblDiskStatus" Content="System Idle - Ready for pre-flight disk check" Foreground="#555555" VerticalAlignment="Center" HorizontalAlignment="Left"/>
            <Button Name="BtnLaunch" Content="Initialize Dual Pipeline" Height="35" HorizontalAlignment="Right" Width="200" FontWeight="Bold"/>
        </Grid>
    </Grid>
</Window>
"@

# ----------------------------------------------------------------------------
# 2. Compile and initialize the WPF window instance
# ----------------------------------------------------------------------------
$Reader = New-Object System.Xml.XmlNodeReader $XAML
$Form   = [Windows.Markup.XamlReader]::Load($Reader)

$TxtSrc        = $Form.FindName("TxtSrc")
$TxtPaOut      = $Form.FindName("TxtPaOut")
$TxtAxOut      = $Form.FindName("TxtAxOut")
$TxtPaExe      = $Form.FindName("TxtPaExe")
$TxtAxExe      = $Form.FindName("TxtAxExe")
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
$Form.FindName("BtnBrowsePa").Add_Click({ $path = Get-LocalFolder "Select Dedicated Target NVMe Partition for PA10"; if ($path) { $TxtPaOut.Text = $path } })
$Form.FindName("BtnBrowseAx").Add_Click({ $path = Get-LocalFolder "Select Dedicated Target NVMe Partition for Magnet Axiom"; if ($path) { $TxtAxOut.Text = $path } })

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

    $Src   = $TxtSrc.Text.Trim()
    $PaOut = $TxtPaOut.Text.Trim()
    $AxOut = $TxtAxOut.Text.Trim()
    $PaExe = $TxtPaExe.Text.Trim()
    $AxExe = $TxtAxExe.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($Src) -or [string]::IsNullOrWhiteSpace($PaOut) -or [string]::IsNullOrWhiteSpace($AxOut)) {
        [System.Windows.MessageBox]::Show("Configuration Error: All target workstation paths must be specified.", "Path Validation Error", "OK", "Error") | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $Src)) {
        [System.Windows.MessageBox]::Show("Source folder not found:`n$Src", "Path Validation Error", "OK", "Error") | Out-Null
        return
    }
    foreach ($dir in @($PaOut, $AxOut)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            try { $null = New-Item -ItemType Directory -Path $dir -Force }
            catch {
                [System.Windows.MessageBox]::Show("Could not create/access target folder:`n$dir`n$($_.Exception.Message)", "Path Validation Error", "OK", "Error") | Out-Null
                return
            }
        }
    }

    $TxtLog.Clear()
    $LblDiskStatus.Content    = "Pre-flight verification running..."
    $LblDiskStatus.Foreground = '#555555'
    $BtnLaunch.IsEnabled      = $false
    Write-PipelineConsole "[+] Pre-flight verification initiated. Processing drive matrix configurations..."

    $script:PipelineJob = Start-Job -Name 'ForensicPipeline' -ScriptBlock {
        param($Src, $PaOut, $AxOut, $PaExe, $AxExe)

        $ErrorActionPreference = 'Stop'
        $MinSpaceBytes = 500GB
        # The source drive is expected to be a read-only pristine repository
        # (see the setup guide), so the run log lives on the PA10 NVMe target
        # instead - which is already confirmed writable by the capacity check.
        $LogFile = Join-Path $PaOut 'ForensicPipeline_RunLog.txt'

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

        if (-not (Test-Path -LiteralPath $PaExe)) {
            Send-Msg "[!] CRITICAL ERROR: PA10 engine not found at '$PaExe'. Verify the software installation path."
            return
        }
        if (-not (Test-Path -LiteralPath $AxExe)) {
            Send-Msg "[!] CRITICAL ERROR: Axiom engine not found at '$AxExe'. Verify the software installation path."
            return
        }

        # Offline disk capacity check (requires minimum 500GB free space on each target drive).
        $PaDisk = Get-DriveInfo $PaOut
        $AxDisk = Get-DriveInfo $AxOut
        if (-not $PaDisk -or -not $AxDisk) {
            Send-Msg "[!] CRITICAL ERROR: Could not resolve a drive letter for one of the target NVMe paths. Use local paths such as E:\Case or F:\Case, not UNC shares."
            return
        }
        if ($PaDisk.FreeSpace -lt $MinSpaceBytes -or $AxDisk.FreeSpace -lt $MinSpaceBytes) {
            Send-Msg ("[!] CRITICAL CAPACITY ERROR: Target drive space insufficient (PA10: {0:N1} GB free, Axiom: {1:N1} GB free). Minimum 500 GB required on each." -f ($PaDisk.FreeSpace / 1GB), ($AxDisk.FreeSpace / 1GB))
            return
        }
        Send-Msg ("[OK] Disk capacity confirmed - PA10 drive: {0:N1} GB free, Axiom drive: {1:N1} GB free." -f ($PaDisk.FreeSpace / 1GB), ($AxDisk.FreeSpace / 1GB))

        $UfdFiles = Get-ChildItem -LiteralPath $Src -Filter '*.ufd' -ErrorAction SilentlyContinue
        if (-not $UfdFiles -or @($UfdFiles).Count -eq 0) {
            Send-Msg "[!] Pipeline halted: zero (.ufd) metadata collections found in '$Src'."
            return
        }

        Send-Msg "[+] Workstation space confirmed. Processing $(@($UfdFiles).Count) mobile case(s) - PA10 and Axiom run in parallel per case, one case at a time."

        $succeeded = 0
        $failed    = 0

        foreach ($File in $UfdFiles) {
            $CaseName = $File.BaseName
            Send-Msg ">>> Spawning dual processing nodes for case file: $CaseName <<<"

            try {
                $PaWorkDir = Join-Path $PaOut "$($CaseName)_PA10_Run"
                $AxWorkDir = Join-Path $AxOut "$($CaseName)_AXIOM_Run"
                $null = New-Item -ItemType Directory -Path $PaWorkDir -Force
                $null = New-Item -ItemType Directory -Path $AxWorkDir -Force

                $BinPath = [System.IO.Path]::ChangeExtension($File.FullName, '.bin')
                if (-not (Test-Path -LiteralPath $BinPath)) { $BinPath = [System.IO.Path]::ChangeExtension($File.FullName, '.tar') }

                Send-Msg "[->] Duplicating forensic collection data arrays to separate NVMe processing units..."
                Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $PaWorkDir $File.Name) -Force
                Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $AxWorkDir $File.Name) -Force

                if (Test-Path -LiteralPath $BinPath) {
                    $BinName = Split-Path $BinPath -Leaf
                    Copy-Item -LiteralPath $BinPath -Destination (Join-Path $PaWorkDir $BinName) -Force
                    Copy-Item -LiteralPath $BinPath -Destination (Join-Path $AxWorkDir $BinName) -Force
                } else {
                    Send-Msg "[~] No sidecar .bin/.tar payload found alongside '$($File.Name)' - continuing with the .ufd metadata only."
                }

                $PaTargetFile   = Join-Path $PaWorkDir $File.Name
                $AxTargetFile   = Join-Path $AxWorkDir $File.Name
                $PaOutputTarget = Join-Path $PaWorkDir 'PA10_Decoded_Case'
                $AxOutputTarget = Join-Path $AxWorkDir 'Axiom_Decoded_Case'

                Send-Msg "[*] Detaching headless engine instances into parallel processing channels..."

                # NOTE: confirm these switches against the CLI reference for your
                # installed PA10 / AXIOM Process build before relying on them.
                $ProcPA = Start-Process -FilePath $PaExe -ArgumentList "-open `"$PaTargetFile`" -method Forensic -project `"$PaOutputTarget`" -examine" -NoNewWindow -PassThru
                $ProcAX = Start-Process -FilePath $AxExe -ArgumentList "/v `"Mobile`" /i `"$AxTargetFile`" /o `"$AxOutputTarget`" /g" -NoNewWindow -PassThru

                $elapsedSeconds = 0
                while (-not $ProcPA.HasExited -or -not $ProcAX.HasExited) {
                    Start-Sleep -Seconds 5
                    $elapsedSeconds += 5
                    if ($elapsedSeconds % 60 -eq 0) {
                        $paState = if ($ProcPA.HasExited) { 'done' } else { 'running' }
                        $axState = if ($ProcAX.HasExited) { 'done' } else { 'running' }
                        Send-Msg ("[...] $CaseName - {0} min elapsed. PA10: {1} | Axiom: {2}" -f [int]($elapsedSeconds / 60), $paState, $axState)
                    }
                }

                $paExit = $ProcPA.ExitCode
                $axExit = $ProcAX.ExitCode
                if ($paExit -eq 0) { Send-Msg "[OK] PA10 completed case '$CaseName' (exit code 0)." }
                else { Send-Msg "[!] PA10 exited with code $paExit for case '$CaseName' - review PA10's own case log." }
                if ($axExit -eq 0) { Send-Msg "[OK] Axiom completed case '$CaseName' (exit code 0)." }
                else { Send-Msg "[!] Axiom exited with code $axExit for case '$CaseName' - review Axiom's own case log." }

                if ($paExit -eq 0 -and $axExit -eq 0) { $succeeded++ } else { $failed++ }
            }
            catch {
                $failed++
                Send-Msg "[!] ERROR processing case '$CaseName': $($_.Exception.Message)"
            }
        }

        Send-Msg "[=] Pipeline finished. $succeeded case(s) fully processed, $failed case(s) with errors. Run log: $LogFile"
    } -ArgumentList $Src, $PaOut, $AxOut, $PaExe, $AxExe

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
