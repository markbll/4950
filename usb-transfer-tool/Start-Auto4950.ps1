<#
.SYNOPSIS
    Auto 49/50 - USB Compression & Transfer Tool - main GUI application.

.DESCRIPTION
    Watches for USB drive arrival, prompts the operator, lets them choose which
    folders/files to capture, tags the capture with a CMS case number, then
    hashes (SHA-256 + MD5), compresses (7-Zip) and transfers the archives to a
    configured network share. Compression and transfer run as a pipeline so the
    first archive starts uploading while the next is still compressing.

    The window shows live Task-Manager-style stats (CPU, memory, network speed,
    temp-folder free space) and a real-time activity log.

.NOTES
    Requires: Windows PowerShell 5.1 (or PowerShell 7 on Windows) and 7-Zip.
    Run:      Right-click -> "Run with PowerShell", or:  powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1
#>

[CmdletBinding()]
param()

# ----------------------------------------------------------------------------
# Bootstrapping
# ----------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$script:AppVersion = '2.0'
$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreModule   = Join-Path $scriptRoot 'Modules\Auto4950.Core.psm1'
$workerModule = Join-Path $scriptRoot 'Modules\Auto4950.Worker.psm1'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

Import-Module $coreModule   -Force
Import-Module $workerModule -Force

$config = Import-A4950Config

# Shared state used to talk to the background worker runspace.
$script:Shared = [hashtable]::Synchronized(@{
    Messages     = [System.Collections.Queue]::Synchronized([System.Collections.Queue]::new())
    Cancel       = $false
    Running      = $false
    Config       = $config
    CoreModule   = $coreModule
    WorkerModule = $workerModule
})
$script:PrevStats    = $null
$script:XferOk       = 0
$script:Prog         = $null
$script:UsbEvents    = [System.Collections.Queue]::Synchronized([System.Collections.Queue]::new())
$script:WorkerPs     = $null
$script:WorkerRs     = $null
$script:WorkerHandle = $null

# ----------------------------------------------------------------------------
# XAML - user interface definition
# ----------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Auto 49/50 - USB Compression &amp; Transfer Tool" Height="820" Width="1460"
        WindowStartupLocation="CenterScreen" WindowState="Maximized" Background="#FF1E1E24" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel"  Color="#FF2A2A33"/>
    <SolidColorBrush x:Key="Accent" Color="#FF4FC3F7"/>
    <SolidColorBrush x:Key="Text"   Color="#FFECECEC"/>
    <SolidColorBrush x:Key="Muted"  Color="#FF9AA0A6"/>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource Text}"/></Style>
    <Style TargetType="Label"><Setter Property="Foreground" Value="{StaticResource Text}"/></Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#FF20202A"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush" Value="#FF444450"/>
      <Setter Property="Padding" Value="4"/>
      <Setter Property="Margin" Value="0,2,0,8"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Margin" Value="0,3"/>
    </Style>
    <Style TargetType="ComboBox"><Setter Property="Margin" Value="0,2,0,8"/></Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Panel}"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="12"/>
      <Setter Property="Margin" Value="6"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#FF3A3A46"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
  </Window.Resources>

  <Grid Margin="8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Border Grid.Row="0" Style="{StaticResource Card}">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <TextBlock FontSize="22" FontWeight="Bold">
              <Run Text="Auto " Foreground="{StaticResource Text}"/><Run Text="49/50" Foreground="{StaticResource Accent}"/>
            </TextBlock>
            <TextBlock x:Name="LblVersion" Text="v0.0.0" Foreground="{StaticResource Muted}" FontSize="12" VerticalAlignment="Bottom" Margin="8,0,0,4"/>
          </StackPanel>
          <TextBlock x:Name="StatusLine" Text="Idle - waiting for a USB drive to be connected." Foreground="{StaticResource Muted}" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnQuick"    Content="Quick Transfer" Background="#FF7B5BD1"/>
          <Button x:Name="BtnRefresh"  Content="Rescan Drives"/>
          <Button x:Name="BtnToggleOptions" Content="Hide Options"/>
          <Button x:Name="BtnHelp"     Content="Help"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Body -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="250"/>
        <ColumnDefinition Width="330"/>
        <ColumnDefinition x:Name="ColOptions" Width="300"/>
        <ColumnDefinition Width="1.5*"/>
      </Grid.ColumnDefinitions>

      <!-- Live system stats -->
      <Border Grid.Column="0" Style="{StaticResource Card}">
        <StackPanel>
          <TextBlock Text="SYSTEM MONITOR" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,0,0,8"/>

          <TextBlock Text="CPU"/>
          <ProgressBar x:Name="BarCpu" Height="14" Minimum="0" Maximum="100" Foreground="#FF66BB6A" Background="#FF20202A"/>
          <TextBlock x:Name="LblCpu" Text="0 %" Foreground="{StaticResource Muted}" Margin="0,2,0,10"/>

          <TextBlock Text="Memory"/>
          <ProgressBar x:Name="BarMem" Height="14" Minimum="0" Maximum="100" Foreground="#FFFFA726" Background="#FF20202A"/>
          <TextBlock x:Name="LblMem" Text="0 % (0 / 0 MB)" Foreground="{StaticResource Muted}" Margin="0,2,0,10"/>

          <TextBlock Text="Network Throughput"/>
          <ProgressBar x:Name="BarNet" Height="14" Minimum="0" Maximum="1000" Foreground="{StaticResource Accent}" Background="#FF20202A"/>
          <TextBlock x:Name="LblNet" Text="0 Mbps" Foreground="{StaticResource Muted}" Margin="0,2,0,10"/>

          <TextBlock Text="Temp Folder Free Space"/>
          <ProgressBar x:Name="BarTemp" Height="14" Minimum="0" Maximum="100" Foreground="#FFAB47BC" Background="#FF20202A"/>
          <TextBlock x:Name="LblTemp" Text="0 GB free" Foreground="{StaticResource Muted}" Margin="0,2,0,10"/>

          <Separator Margin="0,6"/>
          <TextBlock Text="Job Progress" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,4,0,4"/>
          <TextBlock x:Name="LblStage" Text="No job running" Foreground="{StaticResource Muted}" TextWrapping="Wrap"/>
          <ProgressBar x:Name="BarJob" Height="16" Minimum="0" Maximum="100" Foreground="#FF66BB6A" Background="#FF20202A" Margin="0,4,0,0"/>
          <TextBlock x:Name="LblJob" Text="" Foreground="{StaticResource Muted}" Margin="0,2,0,0"/>

          <TextBlock Text="Transfer Status" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,10,0,4"/>
          <TextBlock x:Name="LblXfer" Text="Idle" Foreground="{StaticResource Muted}" TextWrapping="Wrap"/>
          <ProgressBar x:Name="BarXfer" Height="12" Foreground="#FF4FC3F7" Background="#FF20202A" Margin="0,4,0,0"/>
          <TextBlock x:Name="LblXferCount" Text="0 file(s) transferred" Foreground="{StaticResource Muted}" Margin="0,2,0,0"/>
        </StackPanel>
      </Border>

      <!-- Transfer details + selection -->
      <Border Grid.Column="1" Style="{StaticResource Card}">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0">
            <TextBlock Text="CMS CASE NUMBER" FontWeight="Bold" Foreground="{StaticResource Accent}"/>
            <TextBox x:Name="TxtCase" Text="CMS-A" Padding="6" FontSize="14"/>
            <TextBlock x:Name="LblCaseHint" Text="Part of the folder / file name. Must start with the case prefix." Foreground="{StaticResource Muted}" FontSize="11"/>
          </StackPanel>

          <Grid Grid.Row="1" Margin="0,8,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,6,0">
              <TextBlock Text="OP NAME (UPPERCASE)" FontWeight="Bold" Foreground="{StaticResource Accent}"/>
              <TextBox x:Name="TxtOp" Padding="6" FontSize="14" CharacterCasing="Upper"/>
              <TextBlock x:Name="LblOpHint" Text="UPPERCASE. Optional." Foreground="{StaticResource Muted}" FontSize="11"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="6,0,0,0">
              <TextBlock Text="PASS NUMBER" FontWeight="Bold" Foreground="{StaticResource Accent}"/>
              <TextBox x:Name="TxtPass" Padding="6" FontSize="14"/>
              <TextBlock x:Name="LblPassHint" Text="Operator's pass no. Optional." Foreground="{StaticResource Muted}" FontSize="11"/>
            </StackPanel>
          </Grid>

          <TextBlock Grid.Row="2" x:Name="LblNamePreview" Text="File name: (enter a CMS case, OP name or pass number)"
                     Foreground="{StaticResource Muted}" FontStyle="Italic" Margin="0,6,0,0" TextWrapping="Wrap"/>

          <CheckBox Grid.Row="3" x:Name="ChkAuto" Margin="0,8,0,0"
                    Content="Auto-transfer when a USB drive is plugged in (needs CMS case, OP name or pass no.)"/>

          <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="0,8,0,4">
            <TextBlock Text="Source drive:" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <ComboBox x:Name="CmbDrive" Width="120" Foreground="#FF202020" VerticalAlignment="Center"/>
            <Button x:Name="BtnDriveRefresh" Content="Refresh Drives"/>
          </StackPanel>

          <Grid Grid.Row="5" Margin="0,2,0,2">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Selection:" FontWeight="Bold" Foreground="{StaticResource Accent}" VerticalAlignment="Center"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="BtnSelectAll"  Content="Select All"/>
              <Button x:Name="BtnSelectNone" Content="Deselect All"/>
            </StackPanel>
          </Grid>

          <Border Grid.Row="6" Background="#FF20202A" CornerRadius="6" Margin="0,4">
            <TreeView x:Name="TreeItems" Background="Transparent" BorderThickness="0" Foreground="{StaticResource Text}"/>
          </Border>

          <TextBlock Grid.Row="7" x:Name="LblSelCount" Text="0 items selected" Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
        </Grid>
      </Border>

      <!-- Options (all settings, on the main screen) -->
      <Border x:Name="PanelOptions" Grid.Column="2" Style="{StaticResource Card}">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="OPTIONS" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,0,0,6"/>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0">
            <StackPanel>
              <TextBlock Text="Destination (UNC share or local folder)"/>
              <DockPanel>
                <Button x:Name="BtnBrowseNet" Content="Browse..." DockPanel.Dock="Right" Margin="6,2,0,8" Foreground="#FF202020"/>
                <TextBox x:Name="OptNet"/>
              </DockPanel>
              <TextBlock Text="7-Zip path (blank = auto-detect)"/>
              <DockPanel>
                <Button x:Name="BtnBrowse7z" Content="Browse..." DockPanel.Dock="Right" Margin="6,2,0,8" Foreground="#FF202020"/>
                <TextBox x:Name="Opt7z"/>
              </DockPanel>
              <TextBlock Text="Staging folder (local temp)"/>
              <DockPanel>
                <Button x:Name="BtnBrowseStage" Content="Browse..." DockPanel.Dock="Right" Margin="6,2,0,8" Foreground="#FF202020"/>
                <TextBox x:Name="OptStage"/>
              </DockPanel>
              <TextBlock Text="CMS case prefix"/>
              <TextBox x:Name="OptPrefix"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="SIZING / COMPRESSION" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,2,0,4"/>
              <TextBlock Text="Archive format"/>
              <ComboBox x:Name="OptFormat"><ComboBoxItem>zip</ComboBoxItem><ComboBoxItem>7z</ComboBoxItem></ComboBox>
              <TextBlock Text="All selected folders/files are always combined into ONE archive."
                         Foreground="{StaticResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"/>
              <TextBlock Text="Split size (per volume)"/>
              <ComboBox x:Name="OptVolume" IsEditable="True">
                <ComboBoxItem>No split (single file)</ComboBoxItem>
                <ComboBoxItem>500</ComboBoxItem>
                <ComboBoxItem>1024</ComboBoxItem>
                <ComboBoxItem>2048</ComboBoxItem>
                <ComboBoxItem>4096</ComboBoxItem>
                <ComboBoxItem>5120</ComboBoxItem>
                <ComboBoxItem>8192</ComboBoxItem>
              </ComboBox>
              <TextBlock Text="(value in MB; type a custom number or pick a preset)" Foreground="{StaticResource Muted}" FontSize="11" Margin="0,0,0,6"/>
              <TextBlock x:Name="OptLevelLbl" Text="Compression level: 5"/>
              <Slider x:Name="OptLevel" Minimum="0" Maximum="9" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,4,0,8"/>
              <TextBlock Text="Password (AES-256, optional)"/>
              <PasswordBox x:Name="OptPwd" Background="#FF20202A" Foreground="#FFECECEC" BorderBrush="#FF444450" Padding="4" Margin="0,2,0,8"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="HASHING &amp; INTEGRITY" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,2,0,4"/>
              <CheckBox x:Name="OptSha"    Content="Hash SHA-256"/>
              <CheckBox x:Name="OptMd5"    Content="Hash MD5"/>
              <CheckBox x:Name="OptEmbed"  Content="Embed hash manifest in archive"/>
              <CheckBox x:Name="OptVerify" Content="Verify archive at destination"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="BEHAVIOUR" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,2,0,4"/>
              <CheckBox x:Name="OptPrompt"     Content="Prompt on USB insert (when auto-transfer is off)"/>
              <CheckBox x:Name="OptSelDefault" Content="Select all folders/files by default"/>
              <CheckBox x:Name="OptDelete"     Content="Delete temp/staged files once confirmed transferred"/>
              <TextBlock Text="Exclude patterns (comma separated)"/>
              <TextBox x:Name="OptExcl"/>
            </StackPanel>
          </ScrollViewer>
          <Button Grid.Row="2" x:Name="BtnSaveOptions" Content="Save Options" Background="#FF2E7D32" Margin="0,6,0,0"/>
        </Grid>
      </Border>

      <!-- Activity log -->
      <Border Grid.Column="3" Style="{StaticResource Card}">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="REAL-TIME ACTIVITY LOG" FontSize="15" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,0,0,8"/>
          <Border Grid.Row="1" Background="#FF14141A" CornerRadius="6">
            <RichTextBox x:Name="TxtLog" Background="Transparent" Foreground="#FFD4D4D4" BorderThickness="0" Padding="8"
                         FontFamily="Consolas" FontSize="13" IsReadOnly="True"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
          </Border>
        </Grid>
      </Border>
    </Grid>

    <!-- Footer / actions -->
    <Border Grid.Row="2" Style="{StaticResource Card}">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="LblDest" Grid.Column="0" VerticalAlignment="Center" Foreground="{StaticResource Muted}"
                   Text="Destination: (configure in the Options panel)"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="BtnStart"  Content="Start Capture" Background="#FF2E7D32" FontSize="14"/>
          <Button x:Name="BtnCancel" Content="Cancel" Background="#FF8E2A2A" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Grab named controls.
$ctrl = @{}
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $name = $_.Attributes['x:Name'].Value
    if ($name) { $ctrl[$name] = $window.FindName($name) }
}

# ----------------------------------------------------------------------------
# Logging helper (writes coloured lines to the RichTextBox)
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# Notification sounds (Windows system sounds - respects the OS volume/mute)
# ----------------------------------------------------------------------------
$script:LastErrorSoundAt = [DateTime]::MinValue
function Play-A4950ErrorSound {
    # Throttled so a burst of errors doesn't machine-gun the sound.
    if (([DateTime]::Now - $script:LastErrorSoundAt).TotalMilliseconds -lt 400) { return }
    $script:LastErrorSoundAt = [DateTime]::Now
    try { [System.Media.SystemSounds]::Hand.Play() } catch {}
}

function Play-A4950CompletedSound {
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
}

function Add-RtbLine {
    param($Rtb, [string]$Text, [string]$Colour)
    if (-not $Rtb) { return }
    $para = New-Object System.Windows.Documents.Paragraph
    $para.Margin = '0'
    $run = New-Object System.Windows.Documents.Run $Text
    $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Colour)
    $para.Inlines.Add($run)
    $Rtb.Document.Blocks.Add($para)
    while ($Rtb.Document.Blocks.Count -gt 800) {
        $Rtb.Document.Blocks.Remove($Rtb.Document.Blocks.FirstBlock)
    }
    $Rtb.ScrollToEnd()
}

function Add-LogLine {
    param([string]$Text, [string]$Level = 'INFO')
    $colour = switch ($Level) {
        'ERROR' { '#FFEF5350' }
        'WARN'  { '#FFFFCA28' }
        'OK'    { '#FF66BB6A' }
        'STEP'  { '#FF4FC3F7' }
        default { '#FFD4D4D4' }
    }
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text
    Add-RtbLine $ctrl.TxtLog $line $colour
    # Mirror into the transfer-progress popup when it is open.
    if ($script:Prog -and $script:Prog.Log) { Add-RtbLine $script:Prog.Log $line $colour }
    if ($Level -eq 'ERROR') { Play-A4950ErrorSound }
}

# ----------------------------------------------------------------------------
# Drive + tree population
# ----------------------------------------------------------------------------
function Get-RemovableDrives {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2 OR DriveType=3" -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID } |
        Sort-Object DeviceID
}

function Update-DriveList {
    param([string]$Prefer)
    $ctrl.CmbDrive.Items.Clear()
    $drives = Get-RemovableDrives
    foreach ($d in $drives) {
        $label = "{0}  {1}" -f $d.DeviceID, ($(if ($d.VolumeName) { $d.VolumeName } else { '(no label)' }))
        [void]$ctrl.CmbDrive.Items.Add($label)
    }
    if ($ctrl.CmbDrive.Items.Count -gt 0) {
        $sel = 0
        if ($Prefer) {
            for ($i = 0; $i -lt $ctrl.CmbDrive.Items.Count; $i++) {
                if ($ctrl.CmbDrive.Items[$i].ToString().StartsWith($Prefer)) { $sel = $i; break }
            }
        }
        $ctrl.CmbDrive.SelectedIndex = $sel
    }
}

function Get-SelectedDriveRoot {
    if ($ctrl.CmbDrive.SelectedItem) {
        return ($ctrl.CmbDrive.SelectedItem.ToString().Split(' ')[0])  # e.g. "E:"
    }
    return $null
}

$script:SuppressCascade = $false

function Get-NodeCheckBox {
    param($Tvi)
    if ($Tvi -is [System.Windows.Controls.TreeViewItem] -and $Tvi.Header -is [System.Windows.Controls.CheckBox]) { return $Tvi.Header }
    return $null
}

function Set-SubtreeChecked {
    param($Tvi, [bool]$Value)
    foreach ($child in $Tvi.Items) {
        if ($child -is [System.Windows.Controls.TreeViewItem]) {
            $cb = Get-NodeCheckBox $child
            if ($cb) { $cb.IsChecked = $Value }
            Set-SubtreeChecked $child $Value
        }
    }
}

function Clear-Ancestors {
    param($Tvi)
    $p = $Tvi.Parent
    while ($p -is [System.Windows.Controls.TreeViewItem]) {
        $cb = Get-NodeCheckBox $p
        if ($cb -and $cb.IsChecked) { $cb.IsChecked = $false }
        $p = $p.Parent
    }
}

function Invoke-NodeCascade {
    param($Tvi, [bool]$Checked)
    if ($script:SuppressCascade) { return }
    $script:SuppressCascade = $true
    try {
        Set-SubtreeChecked $Tvi $Checked           # cascade down to loaded children
        if (-not $Checked) { Clear-Ancestors $Tvi } # a parent is no longer "fully selected"
    } finally { $script:SuppressCascade = $false }
    Update-SelectionCount
}

function New-TreeCheckItem {
    param([string]$FullPath, [string]$Name, [bool]$IsFolder, [bool]$Checked)
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $(if ($IsFolder) { "[Folder] $Name" } else { "[File]   $Name" })
    $cb.IsChecked = $Checked
    $cb.Foreground = $window.FindResource('Text')
    $tvi = New-Object System.Windows.Controls.TreeViewItem
    $tvi.Header = $cb
    $tvi.Tag = @{ Path = $FullPath; IsFolder = $IsFolder; Loaded = $false }
    # Store a back-reference so event handlers can find the node from the sender.
    $cb.Tag = @{ Path = $FullPath; IsFolder = $IsFolder; Tvi = $tvi }
    $cb.Add_Checked({   param($s, $e) Invoke-NodeCascade $s.Tag.Tvi $true })
    $cb.Add_Unchecked({ param($s, $e) Invoke-NodeCascade $s.Tag.Tvi $false })
    if ($IsFolder) {
        [void]$tvi.Items.Add('...')   # placeholder -> lazy load on expand
        $tvi.Add_Expanded({ param($s, $e) Expand-TreeNode $s })
    }
    return $tvi
}

function Expand-TreeNode {
    param($Tvi)
    if ($Tvi.Tag.Loaded) { return }
    $Tvi.Tag.Loaded = $true
    $Tvi.Items.Clear()
    $parentCb = Get-NodeCheckBox $Tvi
    $parentChecked = [bool]($parentCb -and $parentCb.IsChecked)
    $excl = @($config.ExcludePatterns)
    if ($ctrl.OptExcl) { $excl = @($ctrl.OptExcl.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $script:SuppressCascade = $true   # building nodes must not trigger cascade
    try {
        $kids = Get-ChildItem -LiteralPath $Tvi.Tag.Path -Force -ErrorAction SilentlyContinue |
            Where-Object { $excl -notcontains $_.Name } |
            Sort-Object { -not $_.PSIsContainer }, Name | Select-Object -First 1000
        foreach ($k in $kids) {
            [void]$Tvi.Items.Add((New-TreeCheckItem -FullPath $k.FullName -Name $k.Name -IsFolder $k.PSIsContainer -Checked $parentChecked))
        }
        if ($Tvi.Items.Count -eq 0) {
            $empty = New-Object System.Windows.Controls.TreeViewItem
            $empty.Header = '(empty)'; $empty.Foreground = $window.FindResource('Muted')
            [void]$Tvi.Items.Add($empty)
        }
    } catch {} finally { $script:SuppressCascade = $false }
}

function Update-TreeForDrive {
    $ctrl.TreeItems.Items.Clear()
    $root = Get-SelectedDriveRoot
    if (-not $root) { Update-SelectionCount; return }
    $rootPath = "$root\"
    # Honour the live option controls (so edits take effect without pressing Save).
    $checked = [bool]$config.DefaultSelectAll
    $excl    = @($config.ExcludePatterns)
    if ($ctrl.OptSelDefault) { $checked = [bool]$ctrl.OptSelDefault.IsChecked }
    if ($ctrl.OptExcl)       { $excl = @($ctrl.OptExcl.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $script:SuppressCascade = $true
    try {
        $entries = Get-ChildItem -LiteralPath $rootPath -Force -ErrorAction SilentlyContinue |
            Where-Object { $excl -notcontains $_.Name } |
            Sort-Object { -not $_.PSIsContainer }, Name
        foreach ($e in $entries) {
            [void]$ctrl.TreeItems.Items.Add((New-TreeCheckItem -FullPath $e.FullName -Name $e.Name -IsFolder $e.PSIsContainer -Checked $checked))
        }
    } catch {
        Add-LogLine "Could not read drive $root : $($_.Exception.Message)" 'ERROR'
    } finally { $script:SuppressCascade = $false }
    Update-SelectionCount
}

function Add-CheckedFromNode {
    param($Tvi, $Result)
    $cb = Get-NodeCheckBox $Tvi
    if (-not $cb) { return }
    if ($cb.IsChecked) {
        # Highest checked node covers everything below it -> include and stop.
        $Result.Add($cb.Tag.Path)
        return
    }
    # Unchecked: descend into any loaded children for individually-checked items.
    foreach ($child in $Tvi.Items) {
        if ($child -is [System.Windows.Controls.TreeViewItem]) { Add-CheckedFromNode $child $Result }
    }
}

function Get-CheckedItems {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($tvi in $ctrl.TreeItems.Items) {
        if ($tvi -is [System.Windows.Controls.TreeViewItem]) { Add-CheckedFromNode $tvi $result }
    }
    return $result
}

function Update-SelectionCount {
    $n = (Get-CheckedItems).Count
    $ctrl.LblSelCount.Text = "$n item(s) selected"
}

function Set-AllChecks {
    param([bool]$Value)
    $script:SuppressCascade = $true
    try {
        foreach ($tvi in $ctrl.TreeItems.Items) {
            if ($tvi -is [System.Windows.Controls.TreeViewItem]) {
                $cb = Get-NodeCheckBox $tvi
                if ($cb) { $cb.IsChecked = $Value }
                Set-SubtreeChecked $tvi $Value   # recurse into all loaded sub-folders/files
            }
        }
    } finally { $script:SuppressCascade = $false }
    Update-SelectionCount
}


# ----------------------------------------------------------------------------
# Options panel  <->  config  (all settings live on the main screen)
# ----------------------------------------------------------------------------
function Set-OptionsFromConfig {
    $ctrl.OptNet.Text       = $config.NetworkShare
    $ctrl.Opt7z.Text        = $config.SevenZipPath
    $ctrl.OptStage.Text     = $config.StagingFolder
    $ctrl.OptPrefix.Text    = $config.CasePrefix
    $ctrl.OptVolume.Text    = $(if ([int]$config.VolumeSizeMB -le 0) { 'No split (single file)' } else { [string]([int]$config.VolumeSizeMB) })
    $ctrl.OptLevel.Value    = [double]$config.CompressionLevel
    $ctrl.OptLevelLbl.Text  = "Compression level: $([int]$config.CompressionLevel)"
    $ctrl.OptPwd.Password   = [string]$config.Password
    $ctrl.OptSha.IsChecked        = ($config.HashAlgorithms -contains 'SHA256')
    $ctrl.OptMd5.IsChecked        = ($config.HashAlgorithms -contains 'MD5')
    $ctrl.OptEmbed.IsChecked      = [bool]$config.EmbedManifest
    $ctrl.OptVerify.IsChecked     = [bool]$config.VerifyAfterTransfer
    $ctrl.OptDelete.IsChecked     = [bool]$config.DeleteLocalArchive
    $ctrl.OptPrompt.IsChecked     = [bool]$config.AutoPromptOnInsert
    $ctrl.OptSelDefault.IsChecked = [bool]$config.DefaultSelectAll
    $ctrl.ChkAuto.IsChecked       = [bool]$config.AutoTransfer
    $ctrl.OptExcl.Text            = ($config.ExcludePatterns -join ', ')
    foreach ($it in $ctrl.OptFormat.Items) { if ($it.Content -eq $config.ArchiveFormat) { $ctrl.OptFormat.SelectedItem = $it } }
}

function Sync-OptionsToConfig {
    # Gather the on-screen options back into $config (does not persist to disk).
    $config.NetworkShare  = $ctrl.OptNet.Text.Trim()
    $config.SevenZipPath  = $ctrl.Opt7z.Text.Trim()
    $config.StagingFolder = $ctrl.OptStage.Text.Trim()
    if ($ctrl.OptPrefix.Text.Trim()) { $config.CasePrefix = $ctrl.OptPrefix.Text.Trim() }
    if ($ctrl.OptFormat.SelectedItem) { $config.ArchiveFormat = $ctrl.OptFormat.SelectedItem.Content }
    $config.VolumeSizeMB     = Parse-SplitMB ([string]$ctrl.OptVolume.Text)
    $config.CompressionLevel = [int]$ctrl.OptLevel.Value
    $algs = @(); if ($ctrl.OptSha.IsChecked) { $algs += 'SHA256' }; if ($ctrl.OptMd5.IsChecked) { $algs += 'MD5' }
    if ($algs.Count -eq 0) { $algs = @('SHA256') }
    $config.HashAlgorithms      = $algs
    $config.EmbedManifest       = [bool]$ctrl.OptEmbed.IsChecked
    $config.VerifyAfterTransfer = [bool]$ctrl.OptVerify.IsChecked
    $config.DeleteLocalArchive  = [bool]$ctrl.OptDelete.IsChecked
    $config.AutoPromptOnInsert  = [bool]$ctrl.OptPrompt.IsChecked
    $config.DefaultSelectAll    = [bool]$ctrl.OptSelDefault.IsChecked
    $config.AutoTransfer        = [bool]$ctrl.ChkAuto.IsChecked
    $config.ExcludePatterns     = @($ctrl.OptExcl.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $config.Password            = $ctrl.OptPwd.Password
    $script:Shared.Config       = $config
}

function Save-Options {
    Sync-OptionsToConfig
    Save-A4950Config -Config $config | Out-Null
    Update-Footer
    Add-LogLine 'Options saved to config.json.' 'OK'
    if ($config.Password) { Add-LogLine 'Archive password set (avoid storing sensitive passwords in plain config).' 'WARN' }
}

# ----------------------------------------------------------------------------
# Windows folder/file pickers for locations
# ----------------------------------------------------------------------------
function Select-Folder {
    param([string]$Description, [string]$Start)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($Start -and (Test-Path -LiteralPath $Start)) { $dlg.SelectedPath = $Start }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

function Select-SevenZipFile {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Locate 7z.exe'
    $dlg.Filter = '7-Zip executable (7z.exe;7za.exe)|7z.exe;7za.exe|Executables (*.exe)|*.exe'
    foreach ($seed in @("$env:ProgramW6432\7-Zip", "$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip")) {
        if ($seed -and (Test-Path -LiteralPath $seed)) { $dlg.InitialDirectory = $seed; break }
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return $null
}

# ----------------------------------------------------------------------------
# Quick Transfer: apply the fastest settings
# ----------------------------------------------------------------------------
function Set-QuickTransfer {
    # Warn first: Quick Transfer trades integrity for raw speed.
    $warn = [System.Windows.MessageBox]::Show(
        "QUICK TRANSFER - fastest settings`n`n" +
        "This applies the quickest possible transfer:`n" +
        "  - Store (NO compression)`n" +
        "  - Split into 250 MB files (so parts start transferring as soon as`n" +
        "    each one is written, instead of waiting for one large file)`n" +
        "  - NO hashing  (SHA-256 / MD5 will NOT be calculated)`n" +
        "  - NO manifest`n" +
        "  - NO verification at the destination`n`n" +
        "File integrity will NOT be recorded or verified. Use this only when speed " +
        "matters more than a hash record.`n`nApply Quick Transfer settings?",
        'Quick Transfer - integrity disabled', 'YesNo', 'Warning')
    if ($warn -ne 'Yes') { Add-LogLine 'Quick Transfer cancelled - settings unchanged.' 'INFO'; return }

    # Fastest: store (no compression), split into small (250 MB) parts so each
    # one starts transferring as soon as it's written, no hashing, no manifest,
    # no verify.
    foreach ($it in $ctrl.OptFormat.Items) { if ($it.Content -eq 'zip') { $ctrl.OptFormat.SelectedItem = $it } }
    $ctrl.OptLevel.Value = 0
    $ctrl.OptLevelLbl.Text = 'Compression level: 0'
    $ctrl.OptVolume.Text = '250'
    $ctrl.OptSha.IsChecked    = $false
    $ctrl.OptMd5.IsChecked    = $false
    $ctrl.OptEmbed.IsChecked  = $false   # no manifest -> originals are not hashed
    $ctrl.OptVerify.IsChecked = $false   # no re-hash at destination
    $ctrl.OptDelete.IsChecked = $false
    Sync-OptionsToConfig
    Update-Footer
    Add-LogLine 'Quick Transfer ON: store (no compression), split @ 250 MB, NO hashing, NO verify - fastest throughput.' 'WARN'
}

# ----------------------------------------------------------------------------
# Transfer identifier: any of CMS case (validated) / OP name (UPPERCASE) / Pass no.
# The folder + archive names are built from whichever are supplied, joined by '_'.
# ----------------------------------------------------------------------------
function Get-TransferName {
    $case = $ctrl.TxtCase.Text.Trim()
    $op   = $ctrl.TxtOp.Text.Trim()
    $pass = $ctrl.TxtPass.Text.Trim()
    $caseGiven = $case -and ($case -ne $config.CasePrefix)

    $parts = @(); $kinds = @(); $errs = @()
    if ($caseGiven) {
        if (Test-A4950CaseNumber -CaseNumber $case -Prefix $config.CasePrefix) { $parts += $case; $kinds += 'CMS' }
        else { $errs += "CMS case must start with '$($config.CasePrefix)' and include an identifier." }
    }
    if ($op) {
        if (Test-A4950OpName -Name $op) { $parts += $op; $kinds += 'OP' }
        else { $errs += 'OP name must be UPPERCASE.' }
    }
    if ($pass) {
        $parts += ('PASS' + (New-A4950CaseFolderName -CaseNumber $pass)); $kinds += 'PASS'
    }

    if ($errs.Count) { return [pscustomobject]@{ Ok = $false; Name = $null; Kind = ''; Reason = ($errs -join ' ') } }
    if ($parts.Count -eq 0) {
        return [pscustomobject]@{ Ok = $false; Name = $null; Kind = ''; Reason = "Enter a CMS case (e.g. $($config.CasePrefix)12345), an OP name (UPPERCASE) or a pass number." }
    }
    return [pscustomobject]@{ Ok = $true; Name = ($parts -join '_'); Kind = ($kinds -join '+'); Reason = '' }
}

function Update-NamePreview {
    $tn = Get-TransferName
    if ($tn.Ok) {
        $ctrl.LblNamePreview.Foreground = $window.FindResource('Muted')
        $ctrl.LblNamePreview.Text = "File name: $($tn.Name)__<folder>.$($config.ArchiveFormat)"
    } else {
        $ctrl.LblNamePreview.Foreground = $window.FindResource('Accent')
        $ctrl.LblNamePreview.Text = "File name: $($tn.Reason)"
    }
}

function Parse-SplitMB {
    param([string]$Text)
    if (-not $Text) { return 0 }
    if ($Text -match '(?i)no\s*split') { return 0 }
    if ($Text -match '(\d+)') { return [int]$Matches[1] }
    return 0
}

function Update-Footer {
    $sz = Resolve-SevenZip -PreferredPath $config.SevenZipPath
    if (-not $sz) { $sz = 'NOT FOUND' }
    $split = if ([int]$config.VolumeSizeMB -gt 0) { "Split: $([int]$config.VolumeSizeMB) MB" } else { 'Split: off' }
    $auto  = if ($config.AutoTransfer) { 'Auto: ON' } else { 'Auto: off' }
    $hash  = if ($config.EmbedManifest) { "Hash:$($config.HashAlgorithms -join '+')" } else { 'Hash:OFF' }
    $vfy   = if ($config.VerifyAfterTransfer) { 'Verify:on' } else { 'Verify:off' }
    $ctrl.LblDest.Text = "Dest: $($config.NetworkShare)   |   7-Zip: $sz   |   $($config.ArchiveFormat)  L$($config.CompressionLevel)  $split  $hash  $vfy   |   $auto"
}

# ----------------------------------------------------------------------------
# Transfer-in-progress popup (modeless, mirrors the live events)
# ----------------------------------------------------------------------------
function Show-ProgressWindow {
    param([string]$Name)
    Close-ProgressWindow
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Transfer in progress" Height="560" Width="820" WindowStartupLocation="CenterOwner"
        Background="#FF1E1E24" FontFamily="Segoe UI">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0">
      <TextBlock x:Name="PTitle" Text="Transfer in progress" FontSize="18" FontWeight="Bold" Foreground="#FF4FC3F7"/>
      <TextBlock x:Name="PStatus" Text="Starting..." Foreground="#FF9AA0A6" Margin="0,2,0,8"/>
    </StackPanel>
    <StackPanel Grid.Row="1">
      <TextBlock x:Name="PStage" Text="Preparing..." Foreground="#FFECECEC"/>
      <ProgressBar x:Name="PBarJob" Height="16" Minimum="0" Maximum="100" Foreground="#FF66BB6A" Background="#FF20202A" Margin="0,4,0,8"/>
    </StackPanel>
    <StackPanel Grid.Row="2">
      <TextBlock x:Name="PXfer" Text="Transfer: idle" Foreground="#FFECECEC"/>
      <ProgressBar x:Name="PBarXfer" Height="12" Foreground="#FF4FC3F7" Background="#FF20202A" Margin="0,4,0,2"/>
      <TextBlock x:Name="PCount" Text="0 file(s) transferred" Foreground="#FF9AA0A6" Margin="0,0,0,8"/>
    </StackPanel>
    <Border Grid.Row="3" Background="#FF14141A" CornerRadius="6">
      <RichTextBox x:Name="PLog" Background="Transparent" Foreground="#FFD4D4D4" BorderThickness="0"
                   FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    </Border>
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
      <Button x:Name="PCancel" Content="Cancel Transfer" Padding="14,7" Margin="4" Background="#FF8E2A2A" Foreground="#FFECECEC"/>
      <Button x:Name="PClose"  Content="Close" Padding="14,7" Margin="4" Background="#FF3A3A46" Foreground="#FFECECEC"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $pw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    $pw.Owner = $window
    $g = { param($n) $pw.FindName($n) }
    $script:Prog = @{
        Window = $pw
        Log    = (& $g 'PLog')
        Title  = (& $g 'PTitle')
        Status = (& $g 'PStatus')
        Stage  = (& $g 'PStage')
        BarJob = (& $g 'PBarJob')
        Xfer   = (& $g 'PXfer')
        BarXfer= (& $g 'PBarXfer')
        Count  = (& $g 'PCount')
        Cancel = (& $g 'PCancel')
        Close  = (& $g 'PClose')
    }
    (& $g 'PTitle').Text  = "Transfer in progress - $Name"
    (& $g 'PStatus').Text = "Capturing $Name..."
    (& $g 'PCount').Text  = '0 file(s) transferred'
    (& $g 'PCancel').Add_Click({ Stop-Capture })
    (& $g 'PClose').Add_Click({ Close-ProgressWindow })
    $pw.Add_Closing({ $script:Prog = $null })
    $pw.Show()
}

function Close-ProgressWindow {
    if ($script:Prog -and $script:Prog.Window) {
        $w = $script:Prog.Window
        $script:Prog = $null
        try { $w.Close() } catch {}
    }
}

# ----------------------------------------------------------------------------
# Options panel show/hide (frees the width for a bigger activity log)
# ----------------------------------------------------------------------------
$script:OptionsVisible = $true
function Toggle-OptionsPanel {
    $script:OptionsVisible = -not $script:OptionsVisible
    if ($script:OptionsVisible) {
        $ctrl.ColOptions.Width = [System.Windows.GridLength]::new(300)
        $ctrl.PanelOptions.Visibility = 'Visible'
        $ctrl.BtnToggleOptions.Content = 'Hide Options'
    } else {
        $ctrl.ColOptions.Width = [System.Windows.GridLength]::new(0)
        $ctrl.PanelOptions.Visibility = 'Collapsed'
        $ctrl.BtnToggleOptions.Content = 'Show Options'
    }
}

# ----------------------------------------------------------------------------
# Start / cancel the capture job
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# Destination free-space pre-flight check
# ----------------------------------------------------------------------------
function Show-SpaceWarningDialog {
    param([string]$Message, [bool]$OfferApply)
    [xml]$dx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Destination free space" Height="420" Width="640" WindowStartupLocation="CenterOwner"
        Background="#FF2A2A33" FontFamily="Segoe UI">
  <Grid Margin="16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Destination free space" FontSize="18" FontWeight="Bold" Foreground="#FFFFA726" Margin="0,0,0,8"/>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <TextBlock x:Name="DMsg" TextWrapping="Wrap" Foreground="#FFECECEC" FontSize="13"/>
    </ScrollViewer>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="DApply"    Content="Apply Suggested Settings &amp; Continue" Padding="12,7" Margin="4" Background="#FF2E7D32" Foreground="#FFECECEC"/>
      <Button x:Name="DContinue" Content="Continue Anyway" Padding="12,7" Margin="4" Background="#FFFFA726" Foreground="#FF202020"/>
      <Button x:Name="DCancel"   Content="Cancel" Padding="12,7" Margin="4" Background="#FF3A3A46" Foreground="#FFECECEC"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $dw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dx))
    $dw.Owner = $window
    $g = { param($n) $dw.FindName($n) }
    (& $g 'DMsg').Text = $Message
    if (-not $OfferApply) { (& $g 'DApply').Visibility = 'Collapsed' }
    $script:SpaceDialogResult = 'Cancel'
    (& $g 'DApply').Add_Click({ $script:SpaceDialogResult = 'Apply'; $dw.Close() })
    (& $g 'DContinue').Add_Click({ $script:SpaceDialogResult = 'Continue'; $dw.Close() })
    (& $g 'DCancel').Add_Click({ $script:SpaceDialogResult = 'Cancel'; $dw.Close() })
    [void]$dw.ShowDialog()
    return $script:SpaceDialogResult
}

function Confirm-DestinationSpace {
    <#
    .SYNOPSIS Pre-flight check: estimate source size vs destination free space.
    .DESCRIPTION
        Returns @{ Proceed = [bool]; Note = [string] }. In -Silent mode (used for
        auto-transfer, which must not prompt) a shortfall is logged as a warning
        but never blocks. In interactive mode a shortfall offers to apply a
        suggested format/level that is estimated to fit, continue anyway, or cancel.
    #>
    param([string[]]$Items, [switch]$Silent)

    $prevCursor = $window.Cursor
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    Add-LogLine 'Estimating source size for the destination free-space check...' 'INFO'
    $srcBytes = 0L
    foreach ($it in $Items) { $srcBytes += [int64](Get-A4950PathSizeBytes -Path $it) }
    $window.Cursor = $prevCursor

    $free = Get-A4950FreeSpace -Path $config.NetworkShare
    $ratio = Get-A4950CompressionRatio -Level ([int]$config.CompressionLevel) -Format $config.ArchiveFormat
    $estBytes = [int64]($srcBytes * $ratio * 1.02)

    if (-not $free.Ok) {
        Add-LogLine "Could not determine destination free space: $($free.Error). Proceeding without a space check." 'WARN'
        return @{ Proceed = $true; Note = "Destination free space: unknown (could not query destination)`nEstimated size to send: $(Format-A4950Bytes $estBytes)  (source: $(Format-A4950Bytes $srcBytes))" }
    }

    $safeFree = [int64]($free.FreeBytes * 0.95)   # keep a 5% safety margin
    $note = "Destination free space : $(Format-A4950Bytes $free.FreeBytes)`nEstimated size to send  : $(Format-A4950Bytes $estBytes)  (source: $(Format-A4950Bytes $srcBytes), $($config.ArchiveFormat) level $($config.CompressionLevel))"

    if ($estBytes -lt $safeFree) {
        Add-LogLine "Free space check OK: $(Format-A4950Bytes $free.FreeBytes) free, ~$(Format-A4950Bytes $estBytes) estimated." 'OK'
        return @{ Proceed = $true; Note = $note }
    }

    # Estimate exceeds (or is too close to) the free space.
    if ($Silent) {
        Add-LogLine "WARNING: destination free space may be insufficient - $(Format-A4950Bytes $free.FreeBytes) free, ~$(Format-A4950Bytes $estBytes) estimated needed. Continuing (auto-transfer, no prompts)." 'WARN'
        return @{ Proceed = $true; Note = $note }
    }

    $suggestion = Get-A4950SuggestedCompression -SourceBytes $srcBytes -FreeBytes $safeFree
    if ($suggestion) {
        $msg = "The estimated compressed size may exceed the available free space at the destination.`n`n" +
               "Source data (selected items)                     : $(Format-A4950Bytes $srcBytes)`n" +
               "Current settings ($($config.ArchiveFormat), level $($config.CompressionLevel)) estimate : $(Format-A4950Bytes $estBytes)`n" +
               "Free space at destination                        : $(Format-A4950Bytes $free.FreeBytes)`n`n" +
               "SUGGESTION: switch to $($suggestion.Format) at compression level $($suggestion.Level) - " +
               "estimated size ~$(Format-A4950Bytes $suggestion.EstimatedBytes), which should fit.`n`n" +
               "These are PLANNING ESTIMATES only, not a guarantee - actual compression depends heavily " +
               "on the data. Already-compressed files (photos, video, zips) shrink far less than this."
        $resp = Show-SpaceWarningDialog -Message $msg -OfferApply $true
        switch ($resp) {
            'Apply' {
                foreach ($it in $ctrl.OptFormat.Items) { if ($it.Content -eq $suggestion.Format) { $ctrl.OptFormat.SelectedItem = $it } }
                $ctrl.OptLevel.Value = $suggestion.Level
                $ctrl.OptLevelLbl.Text = "Compression level: $($suggestion.Level)"
                Sync-OptionsToConfig
                Update-Footer
                Add-LogLine "Applied suggested settings: $($suggestion.Format) level $($suggestion.Level) (est. $(Format-A4950Bytes $suggestion.EstimatedBytes))." 'OK'
                return @{ Proceed = $true; Note = "Destination free space : $(Format-A4950Bytes $free.FreeBytes)`nEstimated size to send  : $(Format-A4950Bytes $suggestion.EstimatedBytes)  (adjusted settings: $($suggestion.Format) level $($suggestion.Level))" }
            }
            'Continue' { Add-LogLine 'Continuing with current settings despite a possible space shortfall.' 'WARN'; return @{ Proceed = $true; Note = $note } }
            default    { Add-LogLine 'Capture cancelled at the free-space warning.' 'INFO'; return @{ Proceed = $false } }
        }
    } else {
        $msg = "The selected data is unlikely to fit at the destination even at MAXIMUM compression.`n`n" +
               "Source data (selected items) : $(Format-A4950Bytes $srcBytes)`n" +
               "Free space at destination    : $(Format-A4950Bytes $free.FreeBytes)`n`n" +
               "Consider freeing up space at the destination, selecting fewer items, or choosing a " +
               "different destination.`n`nThis is a PLANNING ESTIMATE only, not a guarantee."
        $resp = Show-SpaceWarningDialog -Message $msg -OfferApply $false
        if ($resp -eq 'Continue') { Add-LogLine 'Continuing despite an estimated space shortfall (no compression setting is expected to fit).' 'WARN'; return @{ Proceed = $true; Note = $note } }
        Add-LogLine 'Capture cancelled at the free-space warning.' 'INFO'
        return @{ Proceed = $false }
    }
}

function Start-Capture {
    param([switch]$NoConfirm)
    if ($script:Shared.Running) { return }

    # Apply the on-screen options first so the capture uses current settings.
    Sync-OptionsToConfig

    $tn = Get-TransferName
    if (-not $tn.Ok) {
        [System.Windows.MessageBox]::Show($tn.Reason, 'Identifier required', 'OK', 'Warning') | Out-Null
        return
    }
    $name = $tn.Name

    $issues = Test-A4950Config -Config $config
    if ($issues.Count) {
        [System.Windows.MessageBox]::Show(($issues -join "`n"), 'Configuration problems', 'OK', 'Warning') | Out-Null
        return
    }

    $items = Get-CheckedItems
    if ($items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one folder or file to capture.', 'Nothing selected', 'OK', 'Warning') | Out-Null
        return
    }

    $caseSafe = New-A4950CaseFolderName $name

    # Pre-flight: estimate source size vs. destination free space; suggest
    # a tighter compression setting (interactively) if it looks like it won't fit.
    $spaceCheck = Confirm-DestinationSpace -Items $items -Silent:$NoConfirm
    if (-not $spaceCheck.Proceed) { return }

    if (-not $NoConfirm) {
        # List each selected item's FULL source path, the destination folder and the
        # single combined archive name. (Re-read $config.ArchiveFormat here - the
        # space check may have just adjusted it.)
        $fmt = $config.ArchiveFormat
        $splitSuffix = if ([int]$config.VolumeSizeMB -gt 0) { ".001, .002, ..." } else { '' }
        $lines = foreach ($it in $items) { "   SOURCE: $it" }
        $maxShow = 15
        $shown = @($lines | Select-Object -First $maxShow)
        if ($items.Count -gt $maxShow) { $shown += "   ... and $($items.Count - $maxShow) more" }
        $archiveNote = "COMBINED into ONE archive - ${caseSafe}.$fmt$splitSuffix`n`nSelected items (full source path):`n$($shown -join "`n")"
        $destPath = Join-Path $config.NetworkShare $caseSafe
        $srcRootFull = "$(Get-SelectedDriveRoot)\"
        $integrity = if ($config.EmbedManifest) {
            "Originals will be hashed ($($config.HashAlgorithms -join ' + '))" +
            $(if ($config.VerifyAfterTransfer) { ' and verified at the destination' } else { ' (no destination verify)' }) + '.'
        } else {
            "WARNING: Quick Transfer - NO hashing and NO verification. File integrity will not be recorded."
        }
        $msg = @"
Capture $($items.Count) selected item(s) as '$name' ($($tn.Kind))?

$($spaceCheck.Note)

Source (full path) : $srcRootFull
Destination folder : $destPath

$archiveNote

$integrity
"@
        $confirm = [System.Windows.MessageBox]::Show($msg, 'Confirm capture', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }
    }

    # Reset transfer status UI.
    $ctrl.LblXfer.Text = 'Starting...'; $ctrl.LblXferCount.Text = '0 file(s) transferred'
    $ctrl.BarXfer.IsIndeterminate = $false; $ctrl.BarXfer.Value = 0
    $script:XferOk = 0

    # Prepare shared state.
    $script:Shared.Config     = $config
    $script:Shared.CaseNumber = $name
    $script:Shared.DriveRoot  = Get-SelectedDriveRoot
    $script:Shared.Items      = @($items)
    $script:Shared.Cancel     = $false
    $script:Shared.Running    = $true
    $script:Shared.LogFile    = Join-Path (Expand-A4950Path $config.StagingFolder) "$caseSafe\$caseSafe.log"

    # Launch worker runspace.
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

    $ctrl.BtnStart.IsEnabled  = $false
    $ctrl.BtnCancel.IsEnabled = $true
    $ctrl.StatusLine.Text = "Capturing $name ($($tn.Kind)) ..."
    Show-ProgressWindow -Name $name          # popup with live events
    Add-LogLine "Capture started for $name ($($tn.Kind))." 'STEP'
}

function Stop-Capture {
    if ($script:Shared.Running) {
        $script:Shared.Cancel = $true      # worker kills 7-Zip/robocopy within ~150 ms
        $ctrl.BtnCancel.IsEnabled = $false
        $ctrl.StatusLine.Text = 'Cancelling - stopping processes and cleaning up temp...'
        $ctrl.LblXfer.Text = 'Cancelling...'
        $ctrl.BarXfer.IsIndeterminate = $false
        Add-LogLine 'Cancel requested - killing active 7-Zip/robocopy and cleaning temp files...' 'WARN'
    }
}

function Complete-Capture {
    $ctrl.BtnStart.IsEnabled  = $true
    $ctrl.BtnCancel.IsEnabled = $false
    $ctrl.StatusLine.Text = 'Idle - waiting for a USB drive to be connected.'
    $ctrl.BarXfer.IsIndeterminate = $false
    if ($ctrl.LblXfer.Text -notmatch 'complete|cancel') { $ctrl.LblXfer.Text = 'Idle' }
    if ($script:WorkerPs) {
        try { $script:WorkerPs.EndInvoke($script:WorkerHandle) } catch {}
        $script:WorkerPs.Dispose(); $script:WorkerRs.Dispose()
        $script:WorkerPs = $null; $script:WorkerRs = $null
    }
}

# ----------------------------------------------------------------------------
# Timers: system stats, worker message pump, USB-event pump
# ----------------------------------------------------------------------------
$statsTimer = New-Object System.Windows.Threading.DispatcherTimer
$statsTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
$statsTimer.Add_Tick({
    $stagePath = Expand-A4950Path $config.StagingFolder
    $tempQualifier = try { Split-Path -Qualifier $stagePath } catch { $env:SystemDrive }
    if (-not $tempQualifier) { $tempQualifier = $env:SystemDrive }
    $s = Get-A4950SystemStats -TempPath "$tempQualifier\" -Previous $script:PrevStats
    if (-not $s) { return }
    $ctrl.BarCpu.Value = $s.CpuPercent;  $ctrl.LblCpu.Text = "$($s.CpuPercent) %"
    $ctrl.BarMem.Value = $s.MemUsedPct;  $ctrl.LblMem.Text = "$($s.MemUsedPct) %  ($([int]$s.MemUsedMB) / $([int]$s.MemTotalMB) MB)"
    $ctrl.BarNet.Maximum = [Math]::Max(100, $s.NetMbps * 1.4)
    $ctrl.BarNet.Value = $s.NetMbps;     $ctrl.LblNet.Text = "$($s.NetMbps) Mbps"
    if ($s.TempTotalGB -gt 0) { $ctrl.BarTemp.Value = 100 * $s.TempFreeGB / $s.TempTotalGB }
    $ctrl.LblTemp.Text = "$($s.TempFreeGB) GB free of $($s.TempTotalGB) GB"
    $script:PrevStats = $s
})

$pumpTimer = New-Object System.Windows.Threading.DispatcherTimer
$pumpTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$pumpTimer.Add_Tick({
  try {
    while ($script:Shared.Messages.Count -gt 0) {
        $m = $script:Shared.Messages.Dequeue()
        $P = $script:Prog
        switch ($m.Type) {
            'log' { Add-LogLine $m.Text $m.Level }
            'progress' {
                switch ($m.Stage) {
                    'item' {
                        $ctrl.LblStage.Text = "Item $($m.Current)/$($m.Total): $($m.Name)"; $ctrl.BarJob.IsIndeterminate = $false; $ctrl.BarJob.Value = 0; $ctrl.LblJob.Text = ''
                        if ($P) { $P.Stage.Text = "Item $($m.Current)/$($m.Total): $($m.Name)"; $P.BarJob.IsIndeterminate = $false; $P.BarJob.Value = 0 }
                    }
                    'hash' {
                        $ctrl.LblStage.Text = "Hashing: $($m.Name)"; $ctrl.BarJob.IsIndeterminate = $false; if ($m.Total) { $ctrl.BarJob.Value = 100 * $m.Current / $m.Total }
                        if ($P) { $P.Stage.Text = "Hashing: $($m.Name)"; $P.BarJob.IsIndeterminate = $false; if ($m.Total) { $P.BarJob.Value = 100 * $m.Current / $m.Total } }
                    }
                    'compress' {
                        $ctrl.LblStage.Text = "Compressing: $($m.Name)"
                        if ([int]$m.Percent -lt 0) { $ctrl.BarJob.IsIndeterminate = $true; $ctrl.LblJob.Text = 'working...' }
                        else { $ctrl.BarJob.IsIndeterminate = $false; $ctrl.BarJob.Value = $m.Percent; $ctrl.LblJob.Text = "$($m.Percent)%" }
                        if ($P) { $P.Stage.Text = "Compressing: $($m.Name)"; $P.BarJob.IsIndeterminate = ([int]$m.Percent -lt 0); if ([int]$m.Percent -ge 0) { $P.BarJob.Value = $m.Percent } }
                    }
                    'xfer' {
                        if ($m.Action -eq 'start') {
                            $ctrl.LblXfer.Text = "Transferring: $($m.Name)"; $ctrl.BarXfer.IsIndeterminate = $true
                            if ($P) { $P.Xfer.Text = "Transferring: $($m.Name)"; $P.BarXfer.IsIndeterminate = $true }
                        } else {
                            $ctrl.BarXfer.IsIndeterminate = $false; $ctrl.BarXfer.Value = 0
                            if ($P) { $P.BarXfer.IsIndeterminate = $false; $P.BarXfer.Value = 0 }
                            if ($m.Ok) {
                                $script:XferOk = [int]$script:XferOk + 1
                                $ctrl.LblXfer.Text = "Transferred: $($m.Name)"; $ctrl.LblXferCount.Text = "$($script:XferOk) file(s) transferred"
                                if ($P) { $P.Xfer.Text = "Transferred: $($m.Name)"; $P.Count.Text = "$($script:XferOk) file(s) transferred" }
                            } else {
                                $ctrl.LblXfer.Text = "Transfer stopped: $($m.Name)"
                                if ($P) { $P.Xfer.Text = "Transfer stopped: $($m.Name)" }
                            }
                        }
                    }
                }
            }
            'done' {
                if ($m.Error) { Add-LogLine "Job ended with error: $($m.Error)" 'ERROR'; $endText = "Error: $($m.Error)" }
                elseif ($m.Cancelled) { Add-LogLine "Cancelled: $($m.Ok) file(s) transferred before stopping; temp cleaned up." 'WARN'; $ctrl.LblXfer.Text = "Cancelled ($($m.Ok) transferred)"; $endText = "Cancelled - $($m.Ok) file(s) transferred" }
                elseif ($m.Fail) { Add-LogLine "Job finished: $($m.Ok) transferred, $($m.Fail) failed. -> $($m.Destination)" 'WARN'; $ctrl.LblXfer.Text = "Complete ($($m.Ok) transferred)"; $endText = "Complete - $($m.Ok) transferred, $($m.Fail) failed"; Play-A4950ErrorSound }
                else { Add-LogLine "Job finished: $($m.Ok) transferred, $($m.Fail) failed. -> $($m.Destination)" 'OK'; $ctrl.LblXfer.Text = "Complete ($($m.Ok) transferred)"; $endText = "Complete - $($m.Ok) transferred, $($m.Fail) failed"; Play-A4950CompletedSound }
                $ctrl.LblStage.Text = 'No job running'; $ctrl.BarJob.IsIndeterminate = $false; $ctrl.BarJob.Value = 0; $ctrl.LblJob.Text = ''
                $ctrl.BarXfer.IsIndeterminate = $false; $ctrl.BarXfer.Value = 0
                if ($P) {
                    $P.Status.Text = $endText; $P.Title.Text = 'Transfer finished'
                    $P.Stage.Text = 'Done'; $P.BarJob.IsIndeterminate = $false; $P.BarJob.Value = 0
                    $P.BarXfer.IsIndeterminate = $false; $P.BarXfer.Value = 0
                    $P.Cancel.IsEnabled = $false
                }
                Complete-Capture
            }
        }
    }
  } catch { Add-LogLine "UI update error: $($_.Exception.Message)" 'ERROR' }
})

$usbTimer = New-Object System.Windows.Threading.DispatcherTimer
$usbTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$usbTimer.Add_Tick({
    while ($script:UsbEvents.Count -gt 0) {
        $drive = $script:UsbEvents.Dequeue()
        # Scan the new drive and list its folders/files for selection.
        Update-DriveList -Prefer $drive
        Update-TreeForDrive
        $n = (Get-CheckedItems).Count
        Add-LogLine "USB drive connected: $drive - scanned, $n item(s) listed." 'STEP'
        $ctrl.StatusLine.Text = "USB drive $drive connected and scanned."
        if ($script:Shared.Running) { continue }

        if ($ctrl.ChkAuto.IsChecked) {
            # Auto-transfer: only needs a valid CMS case OR OP name.
            $tn = Get-TransferName
            if ($tn.Ok) {
                Add-LogLine "Auto-transfer: starting '$($tn.Name)' ($($tn.Kind)) from $drive." 'STEP'
                Start-Capture -NoConfirm
            } else {
                $window.Activate()
                Add-LogLine "Auto-transfer is ON but needs an identifier. $($tn.Reason)" 'WARN'
                [System.Windows.MessageBox]::Show(
                    "USB drive $drive connected and scanned.`n`nAuto-transfer is ON but needs a CMS case or OP name.`n`n$($tn.Reason)",
                    'Auto-transfer - identifier needed', 'OK', 'Warning') | Out-Null
                if ($ctrl.TxtCase.Text.Trim() -eq $config.CasePrefix -or -not $ctrl.TxtCase.Text.Trim()) { $ctrl.TxtCase.Focus(); $ctrl.TxtCase.SelectAll() }
            }
        }
        elseif ($ctrl.OptPrompt.IsChecked) {
            $window.Activate()
            $resp = [System.Windows.MessageBox]::Show(
                "A USB drive ($drive) has been connected and scanned.`n`nReview the folders/files in the middle panel and choose what to transfer.`n`nEnter a CMS case or OP name and start now?",
                'USB drive detected', 'YesNo', 'Question')
            if ($resp -eq 'Yes') {
                $ctrl.TxtCase.Focus(); $ctrl.TxtCase.SelectAll()
                Add-LogLine 'Select folders/files, enter a CMS case or OP name, then press "Start Capture".' 'INFO'
            }
        }
    }
})

# ----------------------------------------------------------------------------
# USB arrival detection via WMI volume-change events
# ----------------------------------------------------------------------------
$script:UsbSubscription = $null
function Register-UsbWatcher {
    try {
        # EventType 2 = device arrival.
        $query = "SELECT * FROM Win32_VolumeChangeEvent WHERE EventType = 2"
        $script:UsbSubscription = Register-CimIndicationEvent -Query $query -SourceIdentifier 'Auto4950UsbArrival' -MessageData $script:UsbEvents -Action {
            $drive = $Event.SourceEventArgs.NewEvent.DriveName
            if ($drive) { $Event.MessageData.Enqueue($drive) }
        } -ErrorAction Stop
        Add-LogLine 'USB watcher active (monitoring for drive arrival).' 'OK'
    } catch {
        Add-LogLine "USB auto-detection unavailable: $($_.Exception.Message). Use 'Rescan Drives'." 'WARN'
    }
}

# ----------------------------------------------------------------------------
# Help window
# ----------------------------------------------------------------------------
function Show-Help {
    $msg = @"
Auto 49/50  (version $script:AppVersion) - USB Compression & Transfer Tool

WORKFLOW
  1. Connect a USB drive. It is scanned automatically and its folders/files are
     listed in the middle panel. Tick what to transfer (all by default); use
     "Select All" / "Deselect All" or untick individual items.
  2. Fill in any of: CMS case (starts with '$($config.CasePrefix)'), OP NAME (UPPERCASE),
     PASS NUMBER. Whatever you provide is combined into the folder/file name
     (e.g. $($config.CasePrefix)12345_JBLOGGS_PASS4471). At least one is required.
  3. Press "Start Capture" and confirm the summary (which lists the folders, the
     destination and the zip names).

QUICK TRANSFER
  The "Quick Transfer" button applies the fastest possible settings: store (no
  compression), split into 250 MB parts (each one starts transferring as soon
  as it's written, rather than waiting for one large file), NO hashing
  (SHA-256/MD5 are not calculated), no manifest and no verification. It warns
  you first, because file integrity is neither recorded nor verified in this
  mode. Use it only when raw transfer speed matters more than a hash record.

CANCEL
  "Cancel" is immediate: it kills the running 7-Zip/robocopy within a fraction
  of a second and deletes the temp files. Any archives already copied stay on
  the share, and a "FAILED TRANSFER" log listing them (with hashes and times)
  is written and sent to the destination.

DESTINATION FREE SPACE
  Before starting, the tool estimates the source size and the compressed size
  at your current settings, and checks that against the free space actually
  available at the destination. If it looks tight, you'll be offered a
  suggested format/level expected to fit - Apply & Continue, Continue Anyway,
  or Cancel. (Auto-transfer skips the dialog and just logs a warning, since it
  must never prompt.) This is a planning ESTIMATE, not a guarantee - already-
  compressed data (photos/video/zips) shrinks far less than typical documents.

TEMP CLEANUP
  Once a file's transfer is CONFIRMED (copied, and hash-verified if
  verification is on), it is deleted from the local staging area immediately.
  When every file in the job is confirmed, the whole temp job folder is
  removed. If anything failed or failed verification, nothing is deleted so
  you can review it. Turn this off in Options ("Delete temp/staged files once
  confirmed transferred") to always keep the local copies.

AUTO-TRANSFER
  Tick "Auto-transfer when a USB drive is plugged in". Then, as soon as a drive
  is connected, the capture starts automatically with NO prompts - it only
  requires that a valid CMS case, OP name or pass number is already entered.
  If none is set you'll be asked to provide one.

COMBINED ARCHIVE
  All selected folders/files are always packed into ONE combined archive (this
  is not configurable) - one manifest covers every selected item, with each
  file's entry prefixed by its original top-level folder name so nothing
  collides.

OPTIONS (all on the main screen, right-hand panel)
  Network share, 7-Zip path, staging folder, case prefix, archive format,
  volume/split size, compression level, password, hashing, manifest embedding,
  verification, prompt-on-insert, select-all default, delete-local and exclude
  patterns. Every option can be toggled/edited and "Save Options" persists them
  to config.json. Options also apply immediately when you press Start.

WHAT HAPPENS
  - Every original file across your whole selection is hashed (SHA-256 / MD5)
    into one manifest.
  - Everything selected is compressed with 7-Zip into ONE archive; the
    manifest is embedded.
  - Large archives are split into volumes ($([int]$config.VolumeSizeMB) MB each by default) so no
    single file is unwieldy. Set the size to 0 for one file. Splitting works for
    both zip and 7z (7-Zip itself only splits .7z, so for zip this tool splits
    the finished archive itself into the same .001/.002/... parts).
  - For a split zip, each volume starts transferring the instant it's fully
    written (.001 is closed before .002 is even started) - no waiting for the
    rest. 7z's own volumes transfer together as one batch once the whole
    7-Zip process has exited, since it can finish its volumes out of numeric
    order internally and there's no safe way to tell from outside.
  - Optionally the transferred archive is re-hashed at the destination to verify.

NAMING
  Destination folder and the archive are named from the CMS case, OP name or
  pass number:
    <share>\$($config.CasePrefix)12345\$($config.CasePrefix)12345.$($config.ArchiveFormat)
  When split, volumes are suffixed .001, .002, ... (open the .001 in 7-Zip to
  reassemble; keep all parts together).

SYSTEM MONITOR
  Live CPU, memory, network throughput and temp-folder free space.

HIDE OPTIONS
  Click "Hide Options" in the header to collapse the Options panel and give
  the Activity Log more room; click "Show Options" to bring it back. Your
  settings are unaffected either way - it only changes what's on screen.

See README.md and docs\USER_GUIDE.md for full documentation.
"@
    [System.Windows.MessageBox]::Show($msg, 'Help', 'OK', 'Information') | Out-Null
}

# ----------------------------------------------------------------------------
# Wire up events
# ----------------------------------------------------------------------------
$ctrl.BtnRefresh.Add_Click({ Update-DriveList; Update-TreeForDrive; Add-LogLine 'Drives rescanned.' 'INFO' })
$ctrl.BtnToggleOptions.Add_Click({ Toggle-OptionsPanel })
$ctrl.BtnDriveRefresh.Add_Click({ Update-DriveList; Update-TreeForDrive; Add-LogLine 'Drives refreshed.' 'INFO' })
$ctrl.BtnHelp.Add_Click({ Show-Help })
$ctrl.BtnQuick.Add_Click({ Set-QuickTransfer })
$ctrl.BtnStart.Add_Click({ Start-Capture })
$ctrl.BtnCancel.Add_Click({ Stop-Capture })
$ctrl.BtnSelectAll.Add_Click({ Set-AllChecks $true })
$ctrl.BtnSelectNone.Add_Click({ Set-AllChecks $false })
$ctrl.BtnSaveOptions.Add_Click({ Save-Options })
$ctrl.BtnBrowseNet.Add_Click({ $p = Select-Folder 'Select the destination folder (UNC share or local path)' $ctrl.OptNet.Text; if ($p) { $ctrl.OptNet.Text = $p } })
$ctrl.BtnBrowseStage.Add_Click({ $p = Select-Folder 'Select the local staging folder' (Expand-A4950Path $ctrl.OptStage.Text); if ($p) { $ctrl.OptStage.Text = $p } })
$ctrl.BtnBrowse7z.Add_Click({ $p = Select-SevenZipFile; if ($p) { $ctrl.Opt7z.Text = $p } })
$ctrl.OptLevel.Add_ValueChanged({ $ctrl.OptLevelLbl.Text = "Compression level: $([int]$ctrl.OptLevel.Value)" })
$ctrl.OptFormat.Add_SelectionChanged({ if ($ctrl.OptFormat.SelectedItem) { $config.ArchiveFormat = $ctrl.OptFormat.SelectedItem.Content; Update-NamePreview } })
$ctrl.CmbDrive.Add_SelectionChanged({ Update-TreeForDrive })
$ctrl.TxtCase.Add_TextChanged({
    $t = $ctrl.TxtCase.Text.Trim()
    $blank = (-not $t) -or ($t -eq $config.CasePrefix)
    $ok = $blank -or (Test-A4950CaseNumber -CaseNumber $t -Prefix $config.CasePrefix)
    $ctrl.LblCaseHint.Foreground = $window.FindResource($(if ($ok) { 'Muted' } else { 'Accent' }))
    $ctrl.LblCaseHint.Text = $(if ($ok) { 'Part of the folder / file name. Must start with the case prefix.' }
                              else { "Must start with '$($config.CasePrefix)' and include an identifier." })
    Update-NamePreview
})
$ctrl.TxtOp.Add_TextChanged({
    $t = $ctrl.TxtOp.Text.Trim()
    $ok = (-not $t) -or (Test-A4950OpName -Name $t)
    $ctrl.LblOpHint.Foreground = $window.FindResource($(if ($ok) { 'Muted' } else { 'Accent' }))
    $ctrl.LblOpHint.Text = $(if ($ok) { 'UPPERCASE. Optional.' } else { 'Must be UPPERCASE.' })
    Update-NamePreview
})
$ctrl.TxtPass.Add_TextChanged({ Update-NamePreview })

$window.Add_Loaded({
    $ctrl.LblVersion.Text = "v$script:AppVersion"
    $window.Title = "Auto 49/50 v$script:AppVersion - USB Compression & Transfer Tool"
    Set-OptionsFromConfig
    Update-DriveList
    Update-TreeForDrive
    Update-Footer
    Update-NamePreview
    Register-UsbWatcher
    $statsTimer.Start(); $pumpTimer.Start(); $usbTimer.Start()
    Add-LogLine "Auto 49/50 v$script:AppVersion ready." 'OK'
    if (-not (Resolve-SevenZip -PreferredPath $config.SevenZipPath)) {
        Add-LogLine '7-Zip not found. Install it (https://www.7-zip.org) or set the 7-Zip path in Options.' 'ERROR'
    }
})

$window.Add_Closing({
    if ($script:Shared.Running) { $script:Shared.Cancel = $true }
    Close-ProgressWindow
    $statsTimer.Stop(); $pumpTimer.Stop(); $usbTimer.Stop()
    Get-EventSubscriber -SourceIdentifier 'Auto4950UsbArrival' -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
})

# ----------------------------------------------------------------------------
# Go
# ----------------------------------------------------------------------------
[void]$window.ShowDialog()
