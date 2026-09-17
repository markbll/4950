<#
.SYNOPSIS
    Auto 49/50 - Kiosk Mode: one-button transfer of a whole external drive.

.DESCRIPTION
    A simplified, full-screen front end for the same compress/hash/transfer
    pipeline the main app uses (Modules/Auto4950.Core.psm1 and
    Auto4950.Worker.psm1) - it reads the same config.json (destination,
    compression, hashing, sounds, etc. - set these up first with Setup.ps1
    or the main app's Options panel), but replaces the full Options/Selection
    UI with a single large button:

      1. Tap the button - a small dialog asks for the CMS case number, the
         pass number, and the source drive (only genuinely external/removable
         drives are listed - see Get-A4950RemovableDrives in Core.psm1).
      2. The ENTIRE selected drive is captured, hashed, compressed and
         transferred - the same as adding that drive's root as a folder in
         the main app, with "Select all folders/files by default" on.
      3. The button turns blue and reads "COMPLETED" with the file name(s)
         that were sent, once the job finishes. Tap it again to start
         another transfer (e.g. for the next drive).

    A failed job turns the button red instead, with the reason; tapping it
    resets back to ready. "Exit Kiosk Mode" (top-right, small and easy to
    ignore by accident) closes the app; it becomes "Cancel Transfer" while a
    job is actually running.

.NOTES
    Requires: Windows PowerShell 5.1 (or PowerShell 7 on Windows) and 7-Zip.
    Run:      Right-click -> "Run with PowerShell", or:  powershell -ExecutionPolicy Bypass -File .\Start-Auto4950-Kiosk.ps1
    Setup.ps1 can create a desktop shortcut (and an auto-start shortcut) for
    this script - see its "Kiosk Mode" section.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:AppVersion = '6.4'
$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreModule   = Join-Path $scriptRoot 'Modules\Auto4950.Core.psm1'
$workerModule = Join-Path $scriptRoot 'Modules\Auto4950.Worker.psm1'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

Import-Module $coreModule   -Force
Import-Module $workerModule -Force

$config = Import-A4950Config

# Shared state used to talk to the background worker runspace - same shape
# Start-Auto4950.ps1 uses, so Invoke-A4950TransferJob needs no changes at all.
$script:Shared = [hashtable]::Synchronized(@{
    Messages     = [System.Collections.Queue]::Synchronized([System.Collections.Queue]::new())
    Cancel       = $false
    Running      = $false
    Config       = $config
    CoreModule   = $coreModule
    WorkerModule = $workerModule
})
$script:WorkerPs     = $null
$script:WorkerRs     = $null
$script:WorkerHandle = $null
$script:LastErrorSoundAt = [DateTime]::MinValue

# ----------------------------------------------------------------------------
# Notification sounds - same config keys and fallback behaviour as the main
# app (Options -> SOUNDS), duplicated locally since this is a standalone
# script with no shared front-end code with Start-Auto4950.ps1.
# ----------------------------------------------------------------------------
function Invoke-A4950KioskSound {
    param([string]$WavPath, [System.Media.SystemSound]$Fallback)
    if ($WavPath -and (Test-Path -LiteralPath $WavPath -PathType Leaf)) {
        try { (New-Object System.Media.SoundPlayer $WavPath).Play(); return } catch {}
    }
    try { $Fallback.Play() } catch {}
}
function Play-KioskStartSound     { Invoke-A4950KioskSound -WavPath $config.SoundStartPath  -Fallback ([System.Media.SystemSounds]::Beep) }
function Play-KioskCompletedSound { Invoke-A4950KioskSound -WavPath $config.SoundFinishPath -Fallback ([System.Media.SystemSounds]::Asterisk) }
function Play-KioskErrorSound {
    if (([DateTime]::Now - $script:LastErrorSoundAt).TotalMilliseconds -lt 400) { return }
    $script:LastErrorSoundAt = [DateTime]::Now
    Invoke-A4950KioskSound -WavPath $config.SoundErrorPath -Fallback ([System.Media.SystemSounds]::Hand)
}

# ----------------------------------------------------------------------------
# Main window - one big card, full screen, no title bar.
# ----------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Auto 49/50 - Kiosk Mode" WindowStyle="None" WindowState="Maximized"
        ResizeMode="NoResize" Background="#FF1E1E24" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="24,18">
      <TextBlock Text="Auto 49/50 - Kiosk Mode" Foreground="#FF9AA0A6" FontSize="16" VerticalAlignment="Center"/>
      <TextBlock x:Name="LblVersion" Text="" Foreground="#FF5A6068" FontSize="12" VerticalAlignment="Bottom" Margin="0,0,140,2" HorizontalAlignment="Right"/>
      <Button x:Name="BtnExit" Content="Exit Kiosk Mode" HorizontalAlignment="Right" Padding="14,8"
              Background="#FF3A3A46" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand"/>
    </Grid>

    <Border Grid.Row="1" x:Name="MainCard" Margin="40" CornerRadius="18" Background="#FF2E7D32" Cursor="Hand">
      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="1400">
        <TextBlock x:Name="MainTitle" Text="TRANSFER" Foreground="White" FontSize="110" FontWeight="Bold"
                   HorizontalAlignment="Center" TextAlignment="Center"/>
        <TextBlock x:Name="MainSubtitle" Text="Tap to begin a new transfer" Foreground="#FFEFEFEF" FontSize="30"
                   HorizontalAlignment="Center" TextAlignment="Center" Margin="0,18,0,0" TextWrapping="Wrap"/>
        <TextBlock x:Name="MainDetail" Text="" Foreground="#FFEFEFEF" FontSize="20" FontFamily="Consolas"
                   HorizontalAlignment="Center" TextAlignment="Center" Margin="0,26,0,0" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
"@
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ctrl = @{}
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $name = $_.Attributes['x:Name'].Value
    if ($name) { $ctrl[$name] = $window.FindName($name) }
}
$ctrl.LblVersion.Text = "v$script:AppVersion"

function Set-MainCard {
    param([string]$Bg, [string]$Title, [string]$Subtitle, [string]$Detail = '')
    $ctrl.MainCard.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Bg)
    $ctrl.MainTitle.Text = $Title
    $ctrl.MainSubtitle.Text = $Subtitle
    $ctrl.MainDetail.Text = $Detail
}

function Reset-MainCard {
    Set-MainCard -Bg '#FF2E7D32' -Title 'TRANSFER' -Subtitle 'Tap to begin a new transfer'
    $ctrl.BtnExit.Content = 'Exit Kiosk Mode'
}

# ----------------------------------------------------------------------------
# "New Transfer" dialog - CMS case, pass number, external source drive.
# ----------------------------------------------------------------------------
function Show-NewTransferDialog {
    [xml]$dxaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="New Transfer" Height="460" Width="560" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#FF2A2A33" FontFamily="Segoe UI">
  <StackPanel Margin="24">
    <TextBlock Text="New Transfer" FontSize="22" FontWeight="Bold" Foreground="#FFECECEC" Margin="0,0,0,4"/>
    <TextBlock Text="Enter the case details and pick the external drive to transfer." Foreground="#FF9AA0A6" TextWrapping="Wrap" Margin="0,0,0,16"/>

    <TextBlock Text="CMS Case Number" Foreground="#FF4FC3F7" FontWeight="Bold" FontSize="14"/>
    <TextBox x:Name="TxtCase" Padding="7" FontSize="16" Background="#FF20202A" Foreground="#FFECECEC" BorderBrush="#FF444450" Margin="0,4,0,14"/>

    <TextBlock Text="Pass Number" Foreground="#FF4FC3F7" FontWeight="Bold" FontSize="14"/>
    <TextBox x:Name="TxtPass" Padding="7" FontSize="16" Background="#FF20202A" Foreground="#FFECECEC" BorderBrush="#FF444450" Margin="0,4,0,14"/>

    <TextBlock Text="Source Drive (external only)" Foreground="#FF4FC3F7" FontWeight="Bold" FontSize="14"/>
    <DockPanel Margin="0,4,0,2">
      <Button x:Name="BtnRefresh" Content="Refresh" DockPanel.Dock="Right" Padding="12,7" Margin="8,0,0,0"
              Background="#FF3A3A46" Foreground="White" BorderThickness="0"/>
      <ComboBox x:Name="CmbDrive" Padding="7" FontSize="15"/>
    </DockPanel>
    <TextBlock x:Name="LblDriveHint" Text="" Foreground="#FFFFCA28" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,4"/>

    <TextBlock x:Name="LblError" Text="" Foreground="#FFEF5350" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,0"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="BtnCancel" Content="Cancel" Padding="18,9" Margin="4" Background="#FF3A3A46" Foreground="White" BorderThickness="0"/>
      <Button x:Name="BtnGo" Content="Start Transfer" Padding="18,9" Margin="4" Background="#FF2E7D32" Foreground="White" BorderThickness="0" FontWeight="Bold"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dxaml))
    $dg = { param($n) $dlg.FindName($n) }
    $dlg.Owner = $window

    (& $dg 'TxtCase').Text = $config.CasePrefix

    function Update-DriveChoices {
        (& $dg 'CmbDrive').Items.Clear()
        $drives = @(Get-A4950RemovableDrives)
        foreach ($d in $drives) {
            $label = "{0}  {1}" -f $d.DeviceID, ($(if ($d.VolumeName) { $d.VolumeName } else { '(no label)' }))
            [void](& $dg 'CmbDrive').Items.Add($label)
        }
        if ((& $dg 'CmbDrive').Items.Count -gt 0) {
            (& $dg 'CmbDrive').SelectedIndex = 0
            (& $dg 'LblDriveHint').Text = ''
        } else {
            (& $dg 'LblDriveHint').Text = 'No external/removable drive detected. Connect one, then click Refresh.'
        }
    }
    Update-DriveChoices
    (& $dg 'BtnRefresh').Add_Click({ Update-DriveChoices })

    $script:KioskDialogResult = $null
    (& $dg 'BtnCancel').Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })
    (& $dg 'BtnGo').Add_Click({
        $case     = (& $dg 'TxtCase').Text.Trim()
        $pass     = (& $dg 'TxtPass').Text.Trim()
        $driveSel = (& $dg 'CmbDrive').SelectedItem

        $errs = @()
        if (-not (Test-A4950CaseNumber -CaseNumber $case -Prefix $config.CasePrefix)) {
            $errs += "CMS case must start with '$($config.CasePrefix)' and include an identifier."
        }
        if (-not $pass) { $errs += 'Enter a pass number.' }
        if (-not $driveSel) { $errs += 'Select an external source drive (connect one and click Refresh if none is listed).' }

        if ($errs.Count) {
            (& $dg 'LblError').Text = ($errs -join ' ')
            return
        }
        $driveRoot = $driveSel.ToString().Split(' ')[0]   # e.g. "E:"
        $script:KioskDialogResult = [pscustomobject]@{ Case = $case; Pass = $pass; DriveRoot = $driveRoot }
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
    return $script:KioskDialogResult
}

# ----------------------------------------------------------------------------
# Start / cancel the transfer
# ----------------------------------------------------------------------------
function Start-KioskTransfer {
    if ($script:Shared.Running) { return }

    $result = Show-NewTransferDialog
    if (-not $result) { return }   # cancelled

    $driveRoot = $result.DriveRoot
    $drivePath = "$driveRoot\"
    if (-not (Test-Path -LiteralPath $drivePath)) {
        Set-MainCard -Bg '#FFB0281E' -Title 'DRIVE NOT FOUND' -Subtitle "$drivePath is no longer available." -Detail 'Tap to try again.'
        Play-KioskErrorSound
        return
    }

    $name     = "$($result.Case)_PASS$($result.Pass)"
    $caseSafe = New-A4950CaseFolderName $name

    $script:Shared.Config     = $config
    $script:Shared.CaseNumber = $name
    $script:Shared.DriveRoot  = $driveRoot
    $script:Shared.Items      = @($drivePath)
    $script:Shared.Cancel     = $false
    $script:Shared.Running    = $true
    $script:Shared.LogFile    = Join-Path (Expand-A4950Path $config.StagingFolder) "$caseSafe\$caseSafe.log"

    $script:WorkerRs = [runspacefactory]::CreateRunspace()
    $script:WorkerRs.ApartmentState = 'MTA'
    $script:WorkerRs.ThreadOptions  = 'ReuseThread'
    $script:WorkerRs.Open()
    $script:WorkerRs.SessionStateProxy.SetVariable('Shared', $script:Shared)
    $script:WorkerPs = [powershell]::Create()
    $script:WorkerPs.Runspace = $script:WorkerRs
    [void]$script:WorkerPs.AddScript({
        param($core, $worker)
        Import-Module $core -Force
        Import-Module $worker -Force
        Invoke-A4950TransferJob -Shared $Shared
    }).AddArgument($coreModule).AddArgument($workerModule)
    $script:WorkerHandle = $script:WorkerPs.BeginInvoke()

    Set-MainCard -Bg '#FFB8860B' -Title 'TRANSFERRING...' -Subtitle $name -Detail "Source: $drivePath`nPlease wait - do not remove the drive."
    $ctrl.BtnExit.Content = 'Cancel Transfer'
    Play-KioskStartSound
}

function Stop-KioskTransfer {
    if ($script:Shared.Running) {
        $script:Shared.Cancel = $true
        $ctrl.MainSubtitle.Text = 'Cancelling - stopping and cleaning up...'
    }
}

function Complete-KioskWorker {
    if ($script:WorkerPs) {
        try { $script:WorkerPs.EndInvoke($script:WorkerHandle) } catch {}
        $script:WorkerPs.Dispose(); $script:WorkerRs.Dispose()
        $script:WorkerPs = $null; $script:WorkerRs = $null
    }
}

# ----------------------------------------------------------------------------
# Event pump - same $Shared.Messages queue the main app drains, simplified
# to only the states the kiosk card actually shows.
# ----------------------------------------------------------------------------
$pumpTimer = New-Object System.Windows.Threading.DispatcherTimer
$pumpTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$pumpTimer.Add_Tick({
  try {
    while ($script:Shared.Messages.Count -gt 0) {
        $m = $script:Shared.Messages.Dequeue()
        switch ($m.Type) {
            'progress' {
                switch ($m.Stage) {
                    'hash'     { $ctrl.MainSubtitle.Text = 'Hashing originals...' }
                    'compress' { $ctrl.MainSubtitle.Text = 'Compressing...' }
                    'xfer'     { if ($m.Action -eq 'start') { $ctrl.MainSubtitle.Text = "Transferring: $($m.Name)" } }
                }
            }
            'done' {
                Complete-KioskWorker
                if ($m.Error) {
                    Set-MainCard -Bg '#FFB0281E' -Title 'TRANSFER FAILED' -Subtitle $m.Error -Detail 'Tap to try again.'
                    Play-KioskErrorSound
                } elseif ($m.Cancelled) {
                    Reset-MainCard
                } elseif ($m.Fail) {
                    Set-MainCard -Bg '#FFB0281E' -Title 'TRANSFER FAILED' `
                        -Subtitle "$($m.Ok) transferred, $($m.Fail) failed" -Detail 'Tap to try again.'
                    Play-KioskErrorSound
                } else {
                    $fileNames = @($m.Files) | Where-Object { $_ -notmatch '_TRANSFER\.log$' }
                    Set-MainCard -Bg '#FF1565C0' -Title 'COMPLETED' `
                        -Subtitle "$($m.Ok) file(s) sent to $($m.Destination)" -Detail ($fileNames -join "`n")
                    Play-KioskCompletedSound
                }
                $ctrl.BtnExit.Content = 'Exit Kiosk Mode'
            }
        }
    }
  } catch {}
})
$pumpTimer.Start()

# ----------------------------------------------------------------------------
# Wire up events
# ----------------------------------------------------------------------------
$ctrl.MainCard.Add_MouseLeftButtonUp({
    if ($script:Shared.Running) { return }   # ignore taps while a job is running - use Cancel Transfer instead
    Start-KioskTransfer
})
$ctrl.BtnExit.Add_Click({
    if ($script:Shared.Running) {
        Stop-KioskTransfer
        return
    }
    $confirm = [System.Windows.MessageBox]::Show('Exit Kiosk Mode?', 'Exit Kiosk Mode', 'YesNo', 'Question')
    if ($confirm -eq 'Yes') { $window.Close() }
})
$window.Add_Closing({
    if ($script:Shared.Running) { $script:Shared.Cancel = $true }
    $pumpTimer.Stop()
})

Reset-MainCard
[void]$window.ShowDialog()
