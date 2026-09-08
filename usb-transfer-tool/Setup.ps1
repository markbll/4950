<#
.SYNOPSIS
    Auto 49/50 - USB Transfer Tool - first-run setup wizard.

.DESCRIPTION
    Creates or edits config.json. Lets you set the network share, locate 7-Zip,
    choose hashing/compression options and test connectivity before saving.
    Run this once before first use (or any time to reconfigure).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptRoot 'Modules\Auto4950.Core.psm1') -Force
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms

# ----------------------------------------------------------------------------
# Execution policy
# ----------------------------------------------------------------------------
# Auto 49/50 ships as unsigned .ps1 scripts. Windows' default execution policy
# ('Restricted' on client editions) blocks them, so users otherwise have to
# launch every time with '-ExecutionPolicy Bypass'. This offers to set a
# per-user 'RemoteSigned' policy once (no administrator rights required), after
# which the scripts can be launched by right-click -> "Run with PowerShell".
function Set-A4950ExecutionPolicy {
    $ok = @('RemoteSigned', 'Unrestricted', 'Bypass')
    try { $effective = Get-ExecutionPolicy } catch { return }
    if ($effective -in $ok) { return }   # already permissive enough

    # If Group Policy is forcing the policy, CurrentUser cannot override it.
    $mp = Get-ExecutionPolicy -Scope MachinePolicy
    $up = Get-ExecutionPolicy -Scope UserPolicy
    if ($mp -ne 'Undefined' -or $up -ne 'Undefined') {
        [System.Windows.MessageBox]::Show(
            "PowerShell's execution policy is '$effective', enforced by Group Policy " +
            "(Machine='$mp', User='$up').`n`nA local override isn't possible. Either ask your " +
            "administrator to allow 'RemoteSigned', or always launch the tool with:`n`n" +
            "    powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1",
            'Execution Policy (managed by Group Policy)', 'OK', 'Warning') | Out-Null
        return
    }

    $ans = [System.Windows.MessageBox]::Show(
        "PowerShell's execution policy is '$effective', which can block Auto 49/50 from running.`n`n" +
        "Set it to 'RemoteSigned' for your user account now?`n`n" +
        "- No administrator rights are required.`n" +
        "- It only affects your account.`n" +
        "- It lets locally-created scripts (this tool) run, while still requiring downloaded scripts to be signed.",
        'Execution Policy', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        [System.Windows.MessageBox]::Show(
            "Done. Your account's execution policy is now 'RemoteSigned'.`n`n" +
            "You can now launch the tool by right-clicking Start-Auto4950.ps1 and choosing " +
            "'Run with PowerShell'.",
            'Execution Policy', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show(
            "Couldn't change the policy automatically:`n$($_.Exception.Message)`n`n" +
            "Run this once in a PowerShell window, then re-open Setup:`n`n" +
            "    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned",
            'Execution Policy', 'OK', 'Error') | Out-Null
    }
}
Set-A4950ExecutionPolicy

$config     = Import-A4950Config
$configPath = Get-ConfigPath

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Auto 49/50 - Setup Wizard" Height="640" Width="640"
        WindowStartupLocation="CenterScreen" Background="#FF2A2A33" FontFamily="Segoe UI">
  <ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="18">
    <TextBlock FontSize="20" FontWeight="Bold">
      <Run Text="Auto " Foreground="#FFECECEC"/><Run Text="49/50" Foreground="#FF4FC3F7"/><Run Text="  -  Setup Wizard" Foreground="#FFECECEC"/>
    </TextBlock>
    <TextBlock Text="Configure destinations and defaults, then Save." Foreground="#FF9AA0A6" Margin="0,0,0,12"/>

    <TextBlock Text="1. Network share (UNC destination)" Foreground="#FFECECEC" FontWeight="SemiBold"/>
    <DockPanel Margin="0,2,0,4">
      <Button x:Name="BtnTestNet" Content="Test" DockPanel.Dock="Right" Padding="12,4" Margin="6,0,0,0" Foreground="#FF202020"/>
      <TextBox x:Name="Net" Padding="5" Background="#FF20202A" Foreground="#FFECECEC"/>
    </DockPanel>
    <TextBlock x:Name="NetStatus" Foreground="#FF9AA0A6" FontSize="11" Margin="0,0,0,10"/>

    <TextBlock Text="2. 7-Zip location" Foreground="#FFECECEC" FontWeight="SemiBold"/>
    <DockPanel Margin="0,2,0,4">
      <Button x:Name="BtnDetect" Content="Auto-detect" DockPanel.Dock="Right" Padding="12,4" Margin="6,0,0,0" Foreground="#FF202020"/>
      <TextBox x:Name="Sz" Padding="5" Background="#FF20202A" Foreground="#FFECECEC"/>
    </DockPanel>
    <TextBlock x:Name="SzStatus" Foreground="#FF9AA0A6" FontSize="11" Margin="0,0,0,10"/>

    <TextBlock Text="3. Staging folder (local, temporary)" Foreground="#FFECECEC" FontWeight="SemiBold"/>
    <TextBox x:Name="Stage" Padding="5" Margin="0,2,0,10" Background="#FF20202A" Foreground="#FFECECEC"/>

    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Margin="0,0,8,0">
        <TextBlock Text="4. Case prefix" Foreground="#FFECECEC" FontWeight="SemiBold"/>
        <TextBox x:Name="Prefix" Padding="5" Margin="0,2,0,10" Background="#FF20202A" Foreground="#FFECECEC"/>
        <TextBlock Text="All selected folders/files are always combined into ONE 7z archive." Foreground="#FF9AA0A6" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <TextBlock Text="Split into volumes of (MB, 0 = single file)" Foreground="#FFECECEC" FontWeight="SemiBold"/>
        <TextBox x:Name="Volume" Padding="5" Margin="0,2,0,10" Background="#FF20202A" Foreground="#FFECECEC"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Margin="8,0,0,0">
        <TextBlock Text="Compression level" Foreground="#FFECECEC" FontWeight="SemiBold"/>
        <Slider x:Name="Level" Minimum="0" Maximum="9" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,6,0,2"/>
        <TextBlock x:Name="LevelLbl" Foreground="#FF9AA0A6" Margin="0,0,0,10"/>
        <CheckBox x:Name="Sha" Content="Hash SHA-256" Foreground="#FFECECEC" Margin="0,2"/>
        <CheckBox x:Name="Md5" Content="Hash MD5" Foreground="#FFECECEC" Margin="0,2"/>
      </StackPanel>
    </Grid>

    <CheckBox x:Name="Embed"  Content="Embed hash manifest inside each archive" Foreground="#FFECECEC" Margin="0,6,0,2"/>
    <CheckBox x:Name="Auto"   Content="Prompt automatically when a USB drive is connected" Foreground="#FFECECEC" Margin="0,2"/>
    <CheckBox x:Name="All"    Content="Select all folders/files by default" Foreground="#FFECECEC" Margin="0,2"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="Save"   Content="Save configuration" Padding="16,7" Margin="4" Background="#FF2E7D32" Foreground="#FFECECEC"/>
      <Button x:Name="Cancel" Content="Close" Padding="16,7" Margin="4" Background="#FF3A3A46" Foreground="#FFECECEC"/>
    </StackPanel>
    <TextBlock x:Name="SaveStatus" Foreground="#FF66BB6A" Margin="0,8,0,0"/>
  </StackPanel>
  </ScrollViewer>
</Window>
"@

$w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$g = { param($n) $w.FindName($n) }

(& $g 'Net').Text    = $config.NetworkShare
(& $g 'Sz').Text     = $config.SevenZipPath
(& $g 'Stage').Text  = $config.StagingFolder
(& $g 'Prefix').Text = $config.CasePrefix
(& $g 'Level').Value  = [double]$config.CompressionLevel
(& $g 'LevelLbl').Text = "Level $($config.CompressionLevel) (0=store, 9=ultra)"
(& $g 'Level').Add_ValueChanged({ (& $g 'LevelLbl').Text = "Level $([int](& $g 'Level').Value) (0=store, 9=ultra)" })
(& $g 'Sha').IsChecked    = ($config.HashAlgorithms -contains 'SHA256')
(& $g 'Md5').IsChecked    = ($config.HashAlgorithms -contains 'MD5')
(& $g 'Embed').IsChecked  = [bool]$config.EmbedManifest
(& $g 'Auto').IsChecked   = [bool]$config.AutoPromptOnInsert
(& $g 'All').IsChecked    = [bool]$config.DefaultSelectAll
(& $g 'Volume').Text = [string]([int]$config.VolumeSizeMB)

(& $g 'BtnTestNet').Add_Click({
    $path = (& $g 'Net').Text.Trim()
    if (Test-Path -LiteralPath $path) {
        (& $g 'NetStatus').Text = "Reachable and writable check..."
        try {
            $probe = Join-Path $path (".bswrite_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
            'probe' | Set-Content -LiteralPath $probe -ErrorAction Stop
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            (& $g 'NetStatus').Text = "OK - share is reachable and writable."
            (& $g 'NetStatus').Foreground = '#FF66BB6A'
        } catch {
            (& $g 'NetStatus').Text = "Reachable but NOT writable: $($_.Exception.Message)"
            (& $g 'NetStatus').Foreground = '#FFFFCA28'
        }
    } else {
        (& $g 'NetStatus').Text = "Not reachable: $path"
        (& $g 'NetStatus').Foreground = '#FFEF5350'
    }
})

(& $g 'BtnDetect').Add_Click({
    $found = Resolve-SevenZip
    if ($found) {
        (& $g 'Sz').Text = $found
        (& $g 'SzStatus').Text = "Found: $found"
        (& $g 'SzStatus').Foreground = '#FF66BB6A'
        return
    }
    # Not auto-detected: let the operator browse to 7z.exe manually.
    (& $g 'SzStatus').Text = '7-Zip not auto-detected. Browse to 7z.exe, or install from https://www.7-zip.org'
    (& $g 'SzStatus').Foreground = '#FFFFCA28'
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Locate 7z.exe (7-Zip command-line executable)'
    $dlg.Filter = '7-Zip executable (7z.exe;7za.exe)|7z.exe;7za.exe|Executables (*.exe)|*.exe'
    foreach ($seed in @("$env:ProgramW6432\7-Zip", "$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip")) {
        if ($seed -and (Test-Path -LiteralPath $seed)) { $dlg.InitialDirectory = $seed; break }
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        (& $g 'Sz').Text = $dlg.FileName
        (& $g 'SzStatus').Text = "Selected: $($dlg.FileName)"
        (& $g 'SzStatus').Foreground = '#FF66BB6A'
    }
})

(& $g 'Cancel').Add_Click({ $w.Close() })
(& $g 'Save').Add_Click({
    $config.NetworkShare        = (& $g 'Net').Text.Trim()
    $config.SevenZipPath        = (& $g 'Sz').Text.Trim()
    $config.StagingFolder       = (& $g 'Stage').Text.Trim()
    $config.CasePrefix          = (& $g 'Prefix').Text.Trim()
    $config.CompressionLevel    = [int](& $g 'Level').Value
    $vol = 0; [void][int]::TryParse((& $g 'Volume').Text.Trim(), [ref]$vol); if ($vol -lt 0) { $vol = 0 }
    $config.VolumeSizeMB        = $vol
    $algs = @(); if ((& $g 'Sha').IsChecked) { $algs += 'SHA256' }; if ((& $g 'Md5').IsChecked) { $algs += 'MD5' }
    if ($algs.Count -eq 0) { $algs = @('SHA256') }
    $config.HashAlgorithms      = $algs
    $config.EmbedManifest       = [bool](& $g 'Embed').IsChecked
    $config.AutoPromptOnInsert  = [bool](& $g 'Auto').IsChecked
    $config.DefaultSelectAll    = [bool](& $g 'All').IsChecked
    Save-A4950Config -Config $config -Path $configPath | Out-Null

    $issues = Test-A4950Config -Config $config
    if ($issues.Count) {
        (& $g 'SaveStatus').Text = "Saved to $configPath (with warnings: $($issues -join '; '))"
        (& $g 'SaveStatus').Foreground = '#FFFFCA28'
    } else {
        (& $g 'SaveStatus').Text = "Saved to $configPath. Configuration valid. You can close and run Start-Auto4950.ps1."
        (& $g 'SaveStatus').Foreground = '#FF66BB6A'
    }
})

[void]$w.ShowDialog()
