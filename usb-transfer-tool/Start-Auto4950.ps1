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
$script:AppVersion = '4.0'
$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreModule   = Join-Path $scriptRoot 'Modules\Auto4950.Core.psm1'
$workerModule = Join-Path $scriptRoot 'Modules\Auto4950.Worker.psm1'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# P/Invoke used solely to enlarge the native Windows folder/file-picker dialogs
# (System.Windows.Forms.FolderBrowserDialog / OpenFileDialog expose no
# Width/Height property of their own) - see Show-EnlargedDialog below.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Auto4950 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    public static class NativeDialog {
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    }
}
'@

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
$script:LastJobStaging = $null   # local staging folder of the last completed job, for "Delete Local Copies"
$script:SuppressDriveBrowse = $false   # true while Update-DriveList sets CmbDrive programmatically
$script:SlowMachineMode = $false
$script:JobQueue     = New-Object System.Collections.Generic.List[object]   # pending [pscustomobject]@{Id;CaseText;OpText;PassText;Name;Items;Config}
$script:QueueRunning = $false   # true once "Start Queue" is clicked, until stopped or the queue empties

# ----------------------------------------------------------------------------
# XAML - user interface definition
# ----------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:sys="clr-namespace:System;assembly=mscorlib"
        Title="Auto 49/50 - USB Compression &amp; Transfer Tool" Height="820" Width="1460"
        WindowStartupLocation="CenterScreen" WindowState="Maximized" Background="{DynamicResource WindowBg}" FontFamily="Segoe UI">
  <Window.Resources>
    <!-- Theme surface colors - all DynamicResource so Dark Mode can swap them
         at runtime (see Set-A4950Theme). Semantic/status colors (buttons like
         Start/Cancel/Quick Transfer, progress bar fills, log line colors) are
         deliberately left as fixed colors - they carry meaning independent of
         light/dark and stay legible either way. -->
    <SolidColorBrush x:Key="WindowBg"    Color="#FF1E1E24"/>
    <SolidColorBrush x:Key="Panel"       Color="#FF2A2A33"/>
    <SolidColorBrush x:Key="Accent"      Color="#FF4FC3F7"/>
    <SolidColorBrush x:Key="Text"        Color="#FFECECEC"/>
    <SolidColorBrush x:Key="Muted"       Color="#FF9AA0A6"/>
    <SolidColorBrush x:Key="InputBg"     Color="#FF20202A"/>
    <SolidColorBrush x:Key="InputBorder" Color="#FF444450"/>
    <SolidColorBrush x:Key="LogBg"       Color="#FF14141A"/>
    <SolidColorBrush x:Key="ButtonBg"    Color="#FF3A3A46"/>

    <!-- Font-size tiers - all DynamicResource so the Font Size option
         (Small/Medium/Large/Extra Large) can rescale every piece of text at
         once (see Set-A4950FontScale). Values here are the Medium defaults. -->
    <sys:Double x:Key="FSTiny">12</sys:Double>
    <sys:Double x:Key="FSBody">13</sys:Double>
    <sys:Double x:Key="FSHeading">15</sys:Double>
    <sys:Double x:Key="FSLarge">14</sys:Double>
    <sys:Double x:Key="FSTitle">22</sys:Double>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
    </Style>
    <Style TargetType="Label">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource InputBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
      <Setter Property="Padding" Value="4"/>
      <Setter Property="Margin" Value="0,2,0,8"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
      <Setter Property="Margin" Value="0,3"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Margin" Value="0,2,0,8"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Panel}"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="12"/>
      <Setter Property="Margin" Value="6"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource ButtonBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="{DynamicResource FSBody}"/>
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
              <Run Text="Auto " Foreground="{DynamicResource Text}"/><Run Text="49/50" Foreground="{DynamicResource Accent}"/>
            </TextBlock>
            <TextBlock x:Name="LblVersion" Text="v0.0.0" Foreground="{DynamicResource Muted}" FontSize="12" VerticalAlignment="Bottom" Margin="8,0,0,4"/>
          </StackPanel>
          <TextBlock x:Name="StatusLine" Text="Idle - waiting for a USB drive to be connected." Foreground="{DynamicResource Muted}" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnQuick"    Content="Quick Transfer" Background="#FF7B5BD1"/>
          <Button x:Name="BtnRefresh"  Content="Rescan Drives"/>
          <Button x:Name="BtnSlowMachine" Content="Slow Machine: OFF" ToolTip="Turns off the System Monitor and forces low-CPU, single-threaded compression - for old or low-spec machines"/>
          <Button x:Name="BtnToggleOptions" Content="Hide Options"/>
          <Button x:Name="BtnHelp"     Content="Help"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Body -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="250"/>
        <ColumnDefinition Width="1.2*"/>
        <ColumnDefinition x:Name="ColOptions" Width="300"/>
        <ColumnDefinition Width="1.2*"/>
      </Grid.ColumnDefinitions>

      <!-- Live system stats -->
      <Border Grid.Column="0" Style="{StaticResource Card}">
        <StackPanel>
          <StackPanel x:Name="PanelSysMonitor">
            <TextBlock Text="SYSTEM MONITOR" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,0,0,8"/>

            <TextBlock Text="CPU"/>
            <ProgressBar x:Name="BarCpu" Height="14" Minimum="0" Maximum="100" Foreground="#FF66BB6A" Background="#FF20202A"/>
            <TextBlock x:Name="LblCpu" Text="0 %" Foreground="{DynamicResource Muted}" Margin="0,2,0,10"/>

            <TextBlock Text="Memory"/>
            <ProgressBar x:Name="BarMem" Height="14" Minimum="0" Maximum="100" Foreground="#FFFFA726" Background="#FF20202A"/>
            <TextBlock x:Name="LblMem" Text="0 % (0 / 0 MB)" Foreground="{DynamicResource Muted}" Margin="0,2,0,10"/>

            <TextBlock Text="Network Throughput"/>
            <ProgressBar x:Name="BarNet" Height="14" Minimum="0" Maximum="1000" Foreground="{DynamicResource Accent}" Background="#FF20202A"/>
            <TextBlock x:Name="LblNet" Text="0 Mbps" Foreground="{DynamicResource Muted}" Margin="0,2,0,10"/>

            <TextBlock Text="Temp Folder Free Space"/>
            <ProgressBar x:Name="BarTemp" Height="14" Minimum="0" Maximum="100" Foreground="#FFAB47BC" Background="#FF20202A"/>
            <TextBlock x:Name="LblTemp" Text="0 GB free" Foreground="{DynamicResource Muted}" Margin="0,2,0,10"/>
            <Separator Margin="0,6"/>
          </StackPanel>
          <TextBlock x:Name="LblSlowMachineNote" Text="System Monitor is off (Slow Machine Mode)." Foreground="{DynamicResource Muted}" FontStyle="Italic" TextWrapping="Wrap" Margin="0,0,0,8" Visibility="Collapsed"/>

          <TextBlock Text="Job Progress" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,4,0,4"/>
          <TextBlock x:Name="LblStage" Text="No job running" Foreground="{DynamicResource Muted}" TextWrapping="Wrap"/>
          <ProgressBar x:Name="BarJob" Height="16" Minimum="0" Maximum="100" Foreground="#FF66BB6A" Background="#FF20202A" Margin="0,4,0,0"/>
          <TextBlock x:Name="LblJob" Text="" Foreground="{DynamicResource Muted}" Margin="0,2,0,0"/>

          <TextBlock Text="Transfer Status" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,10,0,4"/>
          <TextBlock x:Name="LblXfer" Text="Idle" Foreground="{DynamicResource Muted}" TextWrapping="Wrap"/>
          <ProgressBar x:Name="BarXfer" Height="12" Foreground="#FF4FC3F7" Background="#FF20202A" Margin="0,4,0,0"/>
          <TextBlock x:Name="LblXferCount" Text="0 file(s) transferred" Foreground="{DynamicResource Muted}" Margin="0,2,0,0"/>
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
            <TextBlock Text="CMS CASE NUMBER" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
            <TextBox x:Name="TxtCase" Text="CMS-A" Padding="6" FontSize="14"/>
            <TextBlock x:Name="LblCaseHint" Text="Part of the folder / file name. Must start with the case prefix." Foreground="{DynamicResource Muted}" FontSize="11"/>
          </StackPanel>

          <Grid Grid.Row="1" Margin="0,8,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,6,0">
              <TextBlock Text="OP NAME (UPPERCASE)" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
              <TextBox x:Name="TxtOp" Padding="6" FontSize="14" CharacterCasing="Upper"/>
              <TextBlock x:Name="LblOpHint" Text="UPPERCASE. Optional." Foreground="{DynamicResource Muted}" FontSize="11"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="6,0,0,0">
              <TextBlock Text="PASS NUMBER" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
              <TextBox x:Name="TxtPass" Padding="6" FontSize="14"/>
              <TextBlock x:Name="LblPassHint" Text="Operator's pass no. Optional." Foreground="{DynamicResource Muted}" FontSize="11"/>
            </StackPanel>
          </Grid>

          <TextBlock Grid.Row="2" x:Name="LblNamePreview" Text="File name: (enter a CMS case or OP name)"
                     Foreground="{DynamicResource Muted}" FontStyle="Italic" Margin="0,6,0,0" TextWrapping="Wrap"/>

          <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,8,0,4">
            <TextBlock Text="Source drive:" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <ComboBox x:Name="CmbDrive" Width="200" Foreground="#FF202020" VerticalAlignment="Center"/>
            <Button x:Name="BtnDriveRefresh" Content="Refresh Drives"/>
          </StackPanel>

          <StackPanel Grid.Row="4" Margin="0,0,0,4">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnBrowseFolder" Content="Browse Folders..." Foreground="White"/>
              <Button x:Name="BtnBrowseFiles"  Content="Add Files..." Foreground="White"/>
            </StackPanel>
            <TextBlock Text="If the drive isn't listed above, use Browse to add folders (pick one, then choose to add another; sub-folders are included automatically) or Add Files for individual files (multi-select)." Foreground="{DynamicResource Muted}" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
          </StackPanel>

          <Grid Grid.Row="5" Margin="0,2,0,2">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Selection:" FontWeight="Bold" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="BtnClearSelection" Content="Clear Selection"/>
            </StackPanel>
          </Grid>

          <Border Grid.Row="6" Background="#FF20202A" CornerRadius="6" Margin="0,4">
            <ListBox x:Name="LstItems" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Text}"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
          </Border>

          <TextBlock Grid.Row="7" x:Name="LblSelCount" Text="0 items selected" Foreground="{DynamicResource Muted}" Margin="0,4,0,0"/>
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
          <TextBlock Grid.Row="0" Text="OPTIONS" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,0,0,6"/>
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
              <TextBlock Text="SIZING / COMPRESSION" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,4"/>
              <TextBlock Text="Archive format"/>
              <ComboBox x:Name="OptFormat"><ComboBoxItem>zip</ComboBoxItem><ComboBoxItem>7z</ComboBoxItem></ComboBox>
              <TextBlock Text="All selected folders/files are always combined into ONE archive."
                         Foreground="{DynamicResource Muted}" FontSize="{DynamicResource FSTiny}" TextWrapping="Wrap" Margin="0,0,0,8"/>
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
              <TextBlock Text="(value in MB; type a custom number or pick a preset)" Foreground="{DynamicResource Muted}" FontSize="{DynamicResource FSTiny}" Margin="0,0,0,6"/>
              <TextBlock x:Name="OptLevelLbl" Text="Compression level: 5"/>
              <Slider x:Name="OptLevel" Minimum="0" Maximum="9" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,4,0,8"/>
              <TextBlock Text="Password (AES-256, optional)"/>
              <PasswordBox x:Name="OptPwd" Background="{DynamicResource InputBg}" Foreground="{DynamicResource Text}" BorderBrush="{DynamicResource InputBorder}" FontSize="{DynamicResource FSBody}" Padding="4" Margin="0,2,0,8"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="ARCHIVE VOLUME TRANSFER" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,4"/>
              <RadioButton x:Name="OptXferOnComplete" GroupName="XferMode" Content="Wait for All Files" Margin="0,2,0,0" IsChecked="True"/>
              <RadioButton x:Name="OptXferInstant"    GroupName="XferMode" Content="Transfer Immediately" Margin="0,2,0,0"/>
              <TextBlock Text="'Wait for All Files' waits for the whole archive before sending anything - safest, and used automatically when there's no split. 'Transfer Immediately' sends each volume the moment 7-Zip finishes it, rather than waiting for the whole archive; the volume named .001 still always goes last either way, since 7-Zip itself only finalises it at the very end." Foreground="{DynamicResource Muted}" FontSize="{DynamicResource FSTiny}" TextWrapping="Wrap" Margin="0,2,0,6"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="HASHING &amp; INTEGRITY" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,4"/>
              <CheckBox x:Name="OptSha"    Content="Hash SHA-256"/>
              <CheckBox x:Name="OptMd5"    Content="Hash MD5"/>
              <CheckBox x:Name="OptEmbed"  Content="Embed hash manifest in archive"/>
              <CheckBox x:Name="OptVerify" Content="Verify archive at destination"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="BEHAVIOUR" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,4"/>
              <CheckBox x:Name="OptPrompt"     Content="Prompt on USB insert"/>
              <CheckBox x:Name="OptSelDefault" Content="Select all folders/files by default"/>
              <TextBlock Text="Local copies (in the staging folder) are always kept until you delete them - manually, or via &quot;Delete Local Copies&quot; on the transfer-finished window." Foreground="{DynamicResource Muted}" FontSize="{DynamicResource FSTiny}" TextWrapping="Wrap" Margin="0,4,0,4"/>
              <TextBlock Text="Exclude patterns (comma separated)"/>
              <TextBox x:Name="OptExcl"/>

              <Separator Margin="0,6"/>
              <TextBlock Text="SOUNDS" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,4"/>
              <TextBlock Text="Played on start / finish / error. Leave blank to use the standard Windows sound." Foreground="{DynamicResource Muted}" FontSize="{DynamicResource FSTiny}" TextWrapping="Wrap" Margin="0,0,0,6"/>
              <TextBlock Text="Start sound (.wav, optional)"/>
              <DockPanel>
                <Button x:Name="BtnBrowseSoundStart" Content="Browse..." DockPanel.Dock="Right" Margin="6,2,0,8" Foreground="#FF202020"/>
                <TextBox x:Name="OptSoundStart"/>
              </DockPanel>
              <TextBlock Text="Finish sound (.wav, optional)"/>
              <DockPanel>
                <Button x:Name="BtnBrowseSoundFinish" Content="Browse..." DockPanel.Dock="Right" Margin="6,2,0,8" Foreground="#FF202020"/>
                <TextBox x:Name="OptSoundFinish"/>
              </DockPanel>
              <TextBlock Text="Error sound (.wav, optional)"/>
              <DockPanel>
                <Button x:Name="BtnBrowseSoundError" Content="Browse..." DockPanel.Dock="Right" Margin="6,2,0,8" Foreground="#FF202020"/>
                <TextBox x:Name="OptSoundError"/>
              </DockPanel>

              <Separator Margin="0,6"/>
              <TextBlock Text="APPEARANCE" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,2,0,4"/>
              <TextBlock Text="Text size"/>
              <ComboBox x:Name="OptFontSize">
                <ComboBoxItem Tag="Small">Small</ComboBoxItem>
                <ComboBoxItem Tag="Medium">Medium</ComboBoxItem>
                <ComboBoxItem Tag="Large">Large</ComboBoxItem>
                <ComboBoxItem Tag="ExtraLarge">Extra Large</ComboBoxItem>
              </ComboBox>
              <CheckBox x:Name="OptDarkMode" Content="Dark Mode" Margin="0,2,0,0"/>
            </StackPanel>
          </ScrollViewer>
          <Button Grid.Row="2" x:Name="BtnSaveOptions" Content="Save Options" Background="#FF2E7D32" Margin="0,6,0,0"/>
        </Grid>
      </Border>

      <!-- Activity log + job queue -->
      <Border Grid.Column="3" Style="{StaticResource Card}">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="2*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="1*"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="REAL-TIME ACTIVITY LOG" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}" Margin="0,0,0,8"/>
          <Border Grid.Row="1" Background="#FF14141A" CornerRadius="6">
            <RichTextBox x:Name="TxtLog" Background="Transparent" Foreground="#FFD4D4D4" BorderThickness="0" Padding="8"
                         FontFamily="Consolas" FontSize="13" IsReadOnly="True"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
          </Border>

          <Grid Grid.Row="2" Margin="0,10,0,4">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Text="JOB QUEUE" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
              <TextBlock x:Name="LblQueueCount" Text="0 job(s) queued" Foreground="{DynamicResource Muted}" FontSize="11"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="BtnStartQueue" Content="Start Queue" Background="#FF2E7D32" IsEnabled="False"/>
              <Button x:Name="BtnStopQueue"  Content="Stop Queue" Background="#FF8E2A2A" IsEnabled="False"/>
            </StackPanel>
          </Grid>
          <Border Grid.Row="3" Background="#FF14141A" CornerRadius="6">
            <ListBox x:Name="LstQueue" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Text}"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
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
        <TextBlock x:Name="LblDest" Grid.Column="0" VerticalAlignment="Center" Foreground="{DynamicResource Muted}"
                   Text="Destination: (configure in the Options panel)"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="BtnAddQueue" Content="Add to Queue" Background="#FF3A3A80"/>
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

# WPF freezes a Freezable (e.g. SolidColorBrush) resource loaded from a
# ResourceDictionary when it has no dynamic content, making it read-only.
# Set-A4950Theme mutates these brushes' .Color in place, so replace each
# with an unfrozen clone right away - before Add_Loaded/Set-A4950Theme or
# anything else can touch them - otherwise the first theme/mutation attempt
# throws "Cannot modify a frozen SolidColorBrush" with no dialog shown.
foreach ($themeKey in @('WindowBg','Panel','Accent','Text','Muted','InputBg','InputBorder','LogBg','ButtonBg')) {
    $themeBrush = $window.Resources[$themeKey]
    if ($themeBrush -is [System.Windows.Media.SolidColorBrush] -and $themeBrush.IsFrozen) {
        $window.Resources[$themeKey] = $themeBrush.Clone()
    }
}

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
# Notification sounds - an optional .wav per event (Options), falling back to
# a standard Windows system sound (respects the OS volume/mute) when no .wav
# is configured or the configured file can't be found/played.
# ----------------------------------------------------------------------------
$script:LastErrorSoundAt = [DateTime]::MinValue

function Invoke-A4950Sound {
    param([string]$WavPath, [System.Media.SystemSound]$Fallback)
    if ($WavPath -and (Test-Path -LiteralPath $WavPath -PathType Leaf)) {
        try {
            $player = New-Object System.Media.SoundPlayer $WavPath
            $player.Play()
            return
        } catch {
            Add-LogLine "Could not play sound file '$WavPath': $($_.Exception.Message). Using the standard sound instead." 'WARN'
        }
    }
    try { $Fallback.Play() } catch {}
}

function Play-A4950StartSound {
    Invoke-A4950Sound -WavPath $config.SoundStartPath -Fallback ([System.Media.SystemSounds]::Beep)
}

function Play-A4950CompletedSound {
    Invoke-A4950Sound -WavPath $config.SoundFinishPath -Fallback ([System.Media.SystemSounds]::Asterisk)
}

function Play-A4950ErrorSound {
    # Throttled so a burst of errors doesn't machine-gun the sound.
    if (([DateTime]::Now - $script:LastErrorSoundAt).TotalMilliseconds -lt 400) { return }
    $script:LastErrorSoundAt = [DateTime]::Now
    Invoke-A4950Sound -WavPath $config.SoundErrorPath -Fallback ([System.Media.SystemSounds]::Hand)
}

# ----------------------------------------------------------------------------
# Appearance - Dark/Light theme and Small/Medium/Large/Extra Large text size.
# Brushes are mutated in place (not replaced) so both DynamicResource-bound
# XAML and the transfer-progress popup (built from $script:ThemeColors at
# Show-ProgressWindow time) stay in sync; font-size resources are boxed
# doubles so they're replaced wholesale instead.
# ----------------------------------------------------------------------------
$script:ThemeDark = [ordered]@{
    WindowBg='#FF1E1E24'; Panel='#FF2A2A33'; Accent='#FF4FC3F7'; Text='#FFECECEC'; Muted='#FF9AA0A6'
    InputBg='#FF20202A'; InputBorder='#FF444450'; LogBg='#FF14141A'; ButtonBg='#FF3A3A46'
}
$script:ThemeLight = [ordered]@{
    WindowBg='#FFF2F2F5'; Panel='#FFFFFFFF'; Accent='#FF0277BD'; Text='#FF1A1A1A'; Muted='#FF5F6368'
    InputBg='#FFFFFFFF'; InputBorder='#FFC9C9D2'; LogBg='#FFE8E8EC'; ButtonBg='#FFE3E3E9'
}
$script:ThemeColors = $script:ThemeDark
$script:DarkMode = $true

function Set-A4950Theme {
    param([bool]$Dark = $true)
    $script:DarkMode = $Dark
    $palette = if ($Dark) { $script:ThemeDark } else { $script:ThemeLight }
    $script:ThemeColors = $palette
    $converter = New-Object System.Windows.Media.BrushConverter
    foreach ($key in $palette.Keys) {
        $brush = $window.Resources[$key]
        if ($brush -is [System.Windows.Media.SolidColorBrush]) {
            $brush.Color = ($converter.ConvertFromString($palette[$key])).Color
        }
    }
}

$script:FontBaseSizes = @{ FSTiny=12; FSBody=13; FSHeading=15; FSLarge=14; FSTitle=22 }
$script:FontScaleFactors = [ordered]@{ Small=0.85; Medium=1.0; Large=1.15; ExtraLarge=1.35 }

function Set-A4950FontScale {
    param([string]$Size = 'Medium')
    if (-not $script:FontScaleFactors.Contains($Size)) { $Size = 'Medium' }
    $factor = $script:FontScaleFactors[$Size]
    foreach ($key in $script:FontBaseSizes.Keys) {
        $window.Resources[$key] = [double][Math]::Round($script:FontBaseSizes[$key] * $factor, 1)
    }
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

function Get-A4950LogColour {
    <#
    .SYNOPSIS Theme-aware log line colour - the plain dark-theme palette
              reads poorly on a light background, so Light Mode uses darker,
              more saturated variants for the same status meaning.
    #>
    param([string]$Level)
    if ($script:DarkMode -eq $false) {
        switch ($Level) {
            'ERROR' { '#FFC62828' }
            'WARN'  { '#FF8A6D00' }
            'OK'    { '#FF2E7D32' }
            'STEP'  { '#FF01579B' }
            default { '#FF202020' }
        }
    } else {
        switch ($Level) {
            'ERROR' { '#FFEF5350' }
            'WARN'  { '#FFFFCA28' }
            'OK'    { '#FF66BB6A' }
            'STEP'  { '#FF4FC3F7' }
            default { '#FFD4D4D4' }
        }
    }
}

function Add-LogLine {
    param([string]$Text, [string]$Level = 'INFO')
    $colour = Get-A4950LogColour -Level $Level
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text
    Add-RtbLine $ctrl.TxtLog $line $colour
    # Mirror into the transfer-progress popup when it is open.
    if ($script:Prog -and $script:Prog.Log) { Add-RtbLine $script:Prog.Log $line $colour }
    if ($Level -eq 'ERROR') { Play-A4950ErrorSound }
}

# ----------------------------------------------------------------------------
# Drive detection
# ----------------------------------------------------------------------------
function Get-AllDrives {
    # No DriveType filter - list every drive letter Windows exposes (fixed,
    # removable, network, CD/DVD, RAM disk, unknown), so nothing is hidden
    # from the operator. Falls back to Get-PSDrive if WMI/CIM itself is
    # unavailable, instead of silently returning an empty list either way.
    try {
        $disks = @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID } | Sort-Object DeviceID)
        if ($disks.Count -eq 0) { Add-LogLine 'WMI (Win32_LogicalDisk) returned no drives.' 'WARN' }
        return $disks
    } catch {
        Add-LogLine "Drive detection via WMI failed: $($_.Exception.Message) - falling back to Get-PSDrive." 'WARN'
        return @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^[A-Za-z]$' } |
            Sort-Object Name |
            ForEach-Object { [pscustomobject]@{ DeviceID = "$($_.Name):"; VolumeName = $_.Description } })
    }
}

function Update-DriveList {
    param([string]$Prefer)
    # Suppress the "browse this drive" popup on CmbDrive.SelectionChanged while
    # this function sets the list/selection programmatically - it should only
    # fire when the operator picks a drive by hand.
    $script:SuppressDriveBrowse = $true
    try {
        $ctrl.CmbDrive.Items.Clear()
        $drives = Get-AllDrives
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
    } finally {
        $script:SuppressDriveBrowse = $false
    }
}

function Get-SelectedDriveRoot {
    if ($ctrl.CmbDrive.SelectedItem) {
        return ($ctrl.CmbDrive.SelectedItem.ToString().Split(' ')[0])  # e.g. "E:"
    }
    return $null
}

# ----------------------------------------------------------------------------
# Selection: a flat list of top-level folders/files, built entirely from the
# standard Windows folder/file browser dialogs (FolderBrowserDialog, looped
# for multiple folders / OpenFileDialog with Multiselect for files) rather
# than an in-app checkbox tree - navigating to a specific deep sub-folder is
# just normal Explorer navigation inside the dialog, with no custom UI to
# expand level by level. A folder entry is captured recursively, in full, at
# capture time - exactly as a checked folder used to be.
# ----------------------------------------------------------------------------
$script:SelectedItems = New-Object System.Collections.Generic.List[object]   # [pscustomobject]@{ Path; IsFolder }

function Get-SelectedItemPaths {
    return @($script:SelectedItems | ForEach-Object { $_.Path })
}

function Update-SelectionCount {
    $ctrl.LblSelCount.Text = "$($script:SelectedItems.Count) item(s) selected"
}

function Test-TopLevelItemExists {
    param([string]$FullPath)
    return [bool]($script:SelectedItems | Where-Object { $_.Path -eq $FullPath })
}

function New-SelectionListRow {
    param([string]$Path, [bool]$IsFolder)
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = '2,3'
    foreach ($w in @([System.Windows.GridLength]::Auto, [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star), [System.Windows.GridLength]::Auto)) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $w
        [void]$row.ColumnDefinitions.Add($cd)
    }

    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.Text = $(if ($IsFolder) { '[Folder]' } else { '[File]  ' })
    $icon.Foreground = $window.FindResource('Muted')
    $icon.FontFamily = 'Consolas'
    $icon.Margin = '2,0,8,0'
    $icon.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($icon, 0)

    $pathText = New-Object System.Windows.Controls.TextBlock
    $pathText.Text = $Path
    $pathText.Foreground = $window.FindResource('Text')
    $pathText.TextTrimming = 'CharacterEllipsis'
    $pathText.ToolTip = $Path
    $pathText.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($pathText, 1)

    $removeBtn = New-Object System.Windows.Controls.Button
    $removeBtn.Content = 'Remove'
    $removeBtn.Padding = '8,2'
    $removeBtn.Margin = '8,0,2,0'
    $removeBtn.FontSize = 11
    $removeBtn.Tag = $Path
    $removeBtn.Add_Click({ param($s, $e) Remove-SelectedItem -Path $s.Tag }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetColumn($removeBtn, 2)

    [void]$row.Children.Add($icon)
    [void]$row.Children.Add($pathText)
    [void]$row.Children.Add($removeBtn)
    return $row
}

function Add-SelectedItem {
    param([string]$Path, [bool]$IsFolder)
    $Path = $Path.TrimEnd('\')
    if (Test-TopLevelItemExists $Path) { return $false }
    $script:SelectedItems.Add([pscustomobject]@{ Path = $Path; IsFolder = $IsFolder })
    [void]$ctrl.LstItems.Items.Add((New-SelectionListRow -Path $Path -IsFolder $IsFolder))
    Update-SelectionCount
    return $true
}

function Remove-SelectedItem {
    param([string]$Path)
    $idx = -1
    for ($i = 0; $i -lt $script:SelectedItems.Count; $i++) { if ($script:SelectedItems[$i].Path -eq $Path) { $idx = $i; break } }
    if ($idx -lt 0) { return }
    $script:SelectedItems.RemoveAt($idx)
    $ctrl.LstItems.Items.RemoveAt($idx)
    Update-SelectionCount
    Add-LogLine "Removed from selection: $Path" 'INFO'
}

function Clear-Selection {
    $script:SelectedItems.Clear()
    $ctrl.LstItems.Items.Clear()
    Update-SelectionCount
}

# ----------------------------------------------------------------------------
# Job queue: several capture jobs queued up to run one after another
# automatically. Each entry snapshots everything a job needs to run
# independently of whatever is currently on screen - selection, CMS
# case/OP/pass, and a full copy of the options in effect when it was queued -
# so later Options changes (or even another queued job's Edit) can never
# retroactively change a job that's already queued. Queued jobs are run by
# temporarily loading that snapshot onto the main screen and driving the
# existing single-job Start-Capture path unchanged - no separate execution
# code path to keep in sync.
# ----------------------------------------------------------------------------
function Update-QueueCount {
    $ctrl.LblQueueCount.Text = "$($script:JobQueue.Count) job(s) queued"
}

function Copy-OrderedConfig {
    # [ordered]@{} (an OrderedDictionary) has no .Clone() PowerShell can see,
    # so build a new one by hand. Shallow is fine: Sync-OptionsToConfig always
    # replaces array-valued fields (HashAlgorithms, ExcludePatterns) wholesale
    # rather than mutating one in place, so a later edit to the live $config
    # can never reach back into an already-queued snapshot's arrays.
    param($Source)
    $copy = [ordered]@{}
    foreach ($k in $Source.Keys) { $copy[$k] = $Source[$k] }
    return $copy
}

function Get-QueueIndexById {
    param([string]$Id)
    for ($i = 0; $i -lt $script:JobQueue.Count; $i++) { if ($script:JobQueue[$i].Id -eq $Id) { return $i } }
    return -1
}

function New-QueueListRow {
    param($Entry)
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = '2,3'
    foreach ($w in @([System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star), [System.Windows.GridLength]::Auto, [System.Windows.GridLength]::Auto)) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $w
        [void]$row.ColumnDefinitions.Add($cd)
    }

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = "$($Entry.Name)  -  $($Entry.Items.Count) item(s)"
    $label.Foreground = $window.FindResource('Text')
    $label.TextTrimming = 'CharacterEllipsis'
    $label.ToolTip = ($Entry.Items | ForEach-Object { $_.Path }) -join "`n"
    $label.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($label, 0)

    $editBtn = New-Object System.Windows.Controls.Button
    $editBtn.Content = 'Edit'
    $editBtn.Padding = '8,2'
    $editBtn.Margin = '8,0,2,0'
    $editBtn.FontSize = 11
    $editBtn.Tag = $Entry.Id
    $editBtn.Add_Click({ param($s, $e) Edit-QueuedJob -Id $s.Tag }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetColumn($editBtn, 1)

    $removeBtn = New-Object System.Windows.Controls.Button
    $removeBtn.Content = 'Remove'
    $removeBtn.Padding = '8,2'
    $removeBtn.Margin = '2,0,2,0'
    $removeBtn.FontSize = 11
    $removeBtn.Tag = $Entry.Id
    $removeBtn.Add_Click({ param($s, $e) Remove-QueuedJob -Id $s.Tag }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetColumn($removeBtn, 2)

    [void]$row.Children.Add($label)
    [void]$row.Children.Add($editBtn)
    [void]$row.Children.Add($removeBtn)
    return $row
}

function Add-ToQueue {
    # Same pre-flight checks Start-Capture itself does, run up front (while an
    # operator is actually present to see and fix them) rather than only
    # discovered later when the queue auto-advances unattended.
    Sync-OptionsToConfig
    $tn = Get-TransferName
    if (-not $tn.Ok) { [System.Windows.MessageBox]::Show($tn.Reason, 'Identifier required', 'OK', 'Warning') | Out-Null; return }
    $issues = Test-A4950Config -Config $config
    if ($issues.Count) { [System.Windows.MessageBox]::Show(($issues -join "`n"), 'Configuration problems', 'OK', 'Warning') | Out-Null; return }
    $items = Get-SelectedItemPaths
    if ($items.Count -eq 0) { [System.Windows.MessageBox]::Show('Select at least one folder or file to add to the queue.', 'Nothing selected', 'OK', 'Warning') | Out-Null; return }

    $entry = [pscustomobject]@{
        Id       = [guid]::NewGuid().ToString()
        CaseText = $ctrl.TxtCase.Text
        OpText   = $ctrl.TxtOp.Text
        PassText = $ctrl.TxtPass.Text
        Name     = $tn.Name
        Items    = @($script:SelectedItems | ForEach-Object { [pscustomobject]@{ Path = $_.Path; IsFolder = $_.IsFolder } })
        Config   = Copy-OrderedConfig -Source $config
    }
    $script:JobQueue.Add($entry)
    [void]$ctrl.LstQueue.Items.Add((New-QueueListRow -Entry $entry))
    Update-QueueCount
    $ctrl.BtnStartQueue.IsEnabled = (-not $script:QueueRunning)
    Add-LogLine "Added to queue: $($entry.Name) ($($entry.Items.Count) item(s))." 'OK'

    # Clear the current job spec so the operator can build the next one - the
    # Options panel (destination, compression, etc.) is left as-is since
    # that's shared, ambient state, not something tied to one job.
    Clear-Selection
    $ctrl.TxtCase.Text = $config.CasePrefix
    $ctrl.TxtOp.Text = ''
    $ctrl.TxtPass.Text = ''
    Update-NamePreview
}

function Remove-QueuedJob {
    param([string]$Id)
    $idx = Get-QueueIndexById -Id $Id
    if ($idx -lt 0) { return }
    $entry = $script:JobQueue[$idx]
    $script:JobQueue.RemoveAt($idx)
    $ctrl.LstQueue.Items.RemoveAt($idx)
    Update-QueueCount
    $ctrl.BtnStartQueue.IsEnabled = (-not $script:QueueRunning -and $script:JobQueue.Count -gt 0)
    Add-LogLine "Removed from queue: $($entry.Name)." 'INFO'
}

function Restore-QueueEntryToScreen {
    # Shared by Edit-QueuedJob and Start-NextQueuedJob: load a queued entry's
    # snapshot onto the main screen exactly as if the operator had built it
    # by hand - selection, case/OP/pass, and every Options field.
    param($Entry)
    Clear-Selection
    foreach ($it in $Entry.Items) { Add-SelectedItem -Path $it.Path -IsFolder $it.IsFolder | Out-Null }
    $ctrl.TxtCase.Text = $Entry.CaseText
    $ctrl.TxtOp.Text   = $Entry.OpText
    $ctrl.TxtPass.Text = $Entry.PassText
    # Mutate the existing $config object in place (rather than reassigning
    # the variable) - every other function in this script closes over this
    # same object by reference, so a reassignment here would not be seen
    # elsewhere.
    $config.Clear()
    foreach ($k in $Entry.Config.Keys) { $config[$k] = $Entry.Config[$k] }
    Set-OptionsFromConfig
    Set-SlowMachineMode -On ([bool]$config.SlowMachineMode)
    Update-Footer
    Update-NamePreview
}

function Edit-QueuedJob {
    param([string]$Id)
    $idx = Get-QueueIndexById -Id $Id
    if ($idx -lt 0) { return }
    $entry = $script:JobQueue[$idx]
    $script:JobQueue.RemoveAt($idx)
    $ctrl.LstQueue.Items.RemoveAt($idx)
    Update-QueueCount
    $ctrl.BtnStartQueue.IsEnabled = (-not $script:QueueRunning -and $script:JobQueue.Count -gt 0)

    Restore-QueueEntryToScreen -Entry $entry
    Add-LogLine "Recalled from queue for editing: $($entry.Name). Adjust the fields/options, then Start Capture or Add to Queue again." 'INFO'
}

function Start-JobQueue {
    if ($script:JobQueue.Count -eq 0) { Add-LogLine 'Queue is empty - nothing to start.' 'WARN'; return }
    if ($script:QueueRunning) { return }
    $script:QueueRunning = $true
    $ctrl.BtnStartQueue.IsEnabled = $false
    $ctrl.BtnStopQueue.IsEnabled  = $true
    Add-LogLine "Queue started: $($script:JobQueue.Count) job(s) queued." 'STEP'
    Start-NextQueuedJob
}

function Stop-JobQueue {
    if (-not $script:QueueRunning) { return }
    $script:QueueRunning = $false
    $ctrl.BtnStartQueue.IsEnabled = ($script:JobQueue.Count -gt 0)
    $ctrl.BtnStopQueue.IsEnabled  = $false
    Add-LogLine 'Queue stopped - any job already in progress will still finish, but no further queued jobs will start automatically.' 'WARN'
}

function Start-NextQueuedJob {
    # Called both by Start-JobQueue and, on the 'done' event, right after
    # each job wraps up, so the queue advances itself without needing the
    # operator to click anything between jobs.
    if (-not $script:QueueRunning) { return }
    if ($script:Shared.Running) { return }   # something (queue or manual) is already running - this will be called again once it finishes
    if ($script:JobQueue.Count -eq 0) {
        $script:QueueRunning = $false
        $ctrl.BtnStartQueue.IsEnabled = $false
        $ctrl.BtnStopQueue.IsEnabled  = $false
        Add-LogLine 'Queue complete - no more queued jobs.' 'OK'
        return
    }
    $entry = $script:JobQueue[0]
    $script:JobQueue.RemoveAt(0)
    $ctrl.LstQueue.Items.RemoveAt(0)
    Update-QueueCount

    Restore-QueueEntryToScreen -Entry $entry
    Add-LogLine "Queue: starting next job - $($entry.Name) ($($entry.Items.Count) item(s))." 'STEP'
    Start-Capture -NoConfirm
}

function Add-BrowsedFolder {
    # Standard Windows folder browser dialog (one folder per pick), looped so
    # several folders can still be added in one flow. Each picked folder is
    # captured recursively, in full, at capture time - the same as a checked
    # top-level folder used to be.
    $added = 0
    while ($true) {
        $picked = Select-Folder -Description 'Select a source folder to add (all sub-folders and files are included)'
        if (-not $picked) { break }
        if (Add-SelectedItem -Path $picked -IsFolder $true) { $added++ }
        else { Add-LogLine "Folder already in the selection: $picked" 'WARN' }
        $more = [System.Windows.MessageBox]::Show('Add another folder?', 'Browse Folders', 'YesNo', 'Question')
        if ($more -ne 'Yes') { break }
    }
    if ($added -gt 0) { Add-LogLine "$added folder(s) added to selection." 'OK' }
}

function Add-BrowsedFiles {
    # Native multi-select Windows file picker, for individual files.
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title       = 'Select file(s) to add to the selection'
    $dlg.Multiselect = $true
    $dlg.Filter      = 'All files (*.*)|*.*'
    if ((Show-EnlargedDialog -Dialog $dlg) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $added = 0
    foreach ($f in $dlg.FileNames) { if (Add-SelectedItem -Path $f -IsFolder $false) { $added++ } }
    if ($added -gt 0) { Add-LogLine "$added file(s) added to selection." 'OK' }
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
    $ctrl.OptXferInstant.IsChecked    = ($config.TransferMode -eq 'Instant')
    $ctrl.OptXferOnComplete.IsChecked = ($config.TransferMode -ne 'Instant')
    $ctrl.OptLevel.Value    = [double]$config.CompressionLevel
    $ctrl.OptLevelLbl.Text  = "Compression level: $([int]$config.CompressionLevel)"
    $ctrl.OptPwd.Password   = [string]$config.Password
    $ctrl.OptSha.IsChecked        = ($config.HashAlgorithms -contains 'SHA256')
    $ctrl.OptMd5.IsChecked        = ($config.HashAlgorithms -contains 'MD5')
    $ctrl.OptEmbed.IsChecked      = [bool]$config.EmbedManifest
    $ctrl.OptVerify.IsChecked     = [bool]$config.VerifyAfterTransfer
    $ctrl.OptPrompt.IsChecked     = [bool]$config.AutoPromptOnInsert
    $ctrl.OptSelDefault.IsChecked = [bool]$config.DefaultSelectAll
    $ctrl.OptExcl.Text            = ($config.ExcludePatterns -join ', ')
    foreach ($it in $ctrl.OptFormat.Items) { if ($it.Content -eq $config.ArchiveFormat) { $ctrl.OptFormat.SelectedItem = $it } }
    $ctrl.OptSoundStart.Text  = $config.SoundStartPath
    $ctrl.OptSoundFinish.Text = $config.SoundFinishPath
    $ctrl.OptSoundError.Text  = $config.SoundErrorPath
    $ctrl.OptDarkMode.IsChecked = [bool]$config.DarkMode
    foreach ($it in $ctrl.OptFontSize.Items) { if ($it.Tag -eq $config.FontSize) { $ctrl.OptFontSize.SelectedItem = $it } }
}

function Sync-OptionsToConfig {
    # Gather the on-screen options back into $config (does not persist to disk).
    $config.NetworkShare  = $ctrl.OptNet.Text.Trim()
    $config.SevenZipPath  = $ctrl.Opt7z.Text.Trim()
    $config.StagingFolder = $ctrl.OptStage.Text.Trim()
    if ($ctrl.OptPrefix.Text.Trim()) { $config.CasePrefix = $ctrl.OptPrefix.Text.Trim() }
    if ($ctrl.OptFormat.SelectedItem) { $config.ArchiveFormat = $ctrl.OptFormat.SelectedItem.Content }
    $config.VolumeSizeMB     = Parse-SplitMB ([string]$ctrl.OptVolume.Text)
    $config.TransferMode     = if ($ctrl.OptXferInstant.IsChecked) { 'Instant' } else { 'OnComplete' }
    $config.CompressionLevel = [int]$ctrl.OptLevel.Value
    $algs = @(); if ($ctrl.OptSha.IsChecked) { $algs += 'SHA256' }; if ($ctrl.OptMd5.IsChecked) { $algs += 'MD5' }
    if ($algs.Count -eq 0) { $algs = @('SHA256') }
    $config.HashAlgorithms      = $algs
    $config.EmbedManifest       = [bool]$ctrl.OptEmbed.IsChecked
    $config.VerifyAfterTransfer = [bool]$ctrl.OptVerify.IsChecked
    $config.AutoPromptOnInsert  = [bool]$ctrl.OptPrompt.IsChecked
    $config.DefaultSelectAll    = [bool]$ctrl.OptSelDefault.IsChecked
    $config.ExcludePatterns     = @($ctrl.OptExcl.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $config.Password            = $ctrl.OptPwd.Password
    $config.SoundStartPath  = $ctrl.OptSoundStart.Text.Trim()
    $config.SoundFinishPath = $ctrl.OptSoundFinish.Text.Trim()
    $config.SoundErrorPath  = $ctrl.OptSoundError.Text.Trim()
    $config.DarkMode        = [bool]$ctrl.OptDarkMode.IsChecked
    if ($ctrl.OptFontSize.SelectedItem) { $config.FontSize = $ctrl.OptFontSize.SelectedItem.Tag }
    $script:Shared.Config       = $config
}

function Save-Options {
    Sync-OptionsToConfig
    Save-A4950Config -Config $config | Out-Null
    Update-Footer
    Add-LogLine 'Options saved to config.json.' 'OK'
    if ($config.Password) { Add-LogLine 'Archive password set (avoid storing sensitive passwords in plain config).' 'WARN' }
    Hide-OptionsPanel
}

# ----------------------------------------------------------------------------
# Windows folder/file pickers for locations
# ----------------------------------------------------------------------------
function Show-EnlargedDialog {
    <#
    .SYNOPSIS Show a System.Windows.Forms common dialog (OpenFileDialog /
              FolderBrowserDialog) enlarged beyond its default size.
    .DESCRIPTION
        Neither dialog exposes a Width/Height property, so there's no direct
        way to ask for a bigger one. Instead, a short-interval timer polls
        for the dialog's own top-level window - identified as the foreground
        window that belongs to our process but ISN'T our main window - right
        after ShowDialog() opens it, and grows it in place via SetWindowPos.
        Runs at most once per call; harmless no-op if the window is never
        matched (e.g. the dialog is closed before the first poll).
    #>
    param(
        [Parameter(Mandatory)] $Dialog,
        [int]$MinWidth = 1000,
        [int]$MinHeight = 680
    )
    $mainHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    $myPid    = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100
    $timer.Add_Tick({
        $hwnd = [Auto4950.NativeDialog]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero -or $hwnd -eq $mainHwnd) { return }
        $tpid = 0
        [void][Auto4950.NativeDialog]::GetWindowThreadProcessId($hwnd, [ref]$tpid)
        if ($tpid -ne $myPid) { return }
        $rect = New-Object Auto4950.RECT
        if ([Auto4950.NativeDialog]::GetWindowRect($hwnd, [ref]$rect)) {
            $w = $rect.Right - $rect.Left
            $h = $rect.Bottom - $rect.Top
            if ($w -lt $MinWidth -or $h -lt $MinHeight) {
                [void][Auto4950.NativeDialog]::SetWindowPos($hwnd, [IntPtr]::Zero, $rect.Left, $rect.Top, [Math]::Max($w, $MinWidth), [Math]::Max($h, $MinHeight), 0x0004)
            }
        }
        $timer.Stop()
    }.GetNewClosure())
    $timer.Start()
    try {
        return $Dialog.ShowDialog()
    } finally {
        $timer.Stop()
        $timer.Dispose()
    }
}

function Select-Folder {
    param([string]$Description, [string]$Start)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($Start -and (Test-Path -LiteralPath $Start)) { $dlg.SelectedPath = $Start }
    if ((Show-EnlargedDialog -Dialog $dlg) -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

function Select-SevenZipFile {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Locate 7z.exe'
    $dlg.Filter = '7-Zip executable (7z.exe;7za.exe)|7z.exe;7za.exe|Executables (*.exe)|*.exe'
    foreach ($seed in @("$env:ProgramW6432\7-Zip", "$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip")) {
        if ($seed -and (Test-Path -LiteralPath $seed)) { $dlg.InitialDirectory = $seed; break }
    }
    if ((Show-EnlargedDialog -Dialog $dlg) -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return $null
}

function Select-WavFile {
    param([string]$Title = 'Select a .wav sound file')
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = $Title
    $dlg.Filter = 'WAV audio (*.wav)|*.wav|All files (*.*)|*.*'
    if ((Show-EnlargedDialog -Dialog $dlg) -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
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
    $ctrl.OptXferInstant.IsChecked = $true   # each part transfers the moment it's ready, not once the whole archive is done
    $ctrl.OptSha.IsChecked    = $false
    $ctrl.OptMd5.IsChecked    = $false
    $ctrl.OptEmbed.IsChecked  = $false   # no manifest -> originals are not hashed
    $ctrl.OptVerify.IsChecked = $false   # no re-hash at destination
    Sync-OptionsToConfig
    Update-Footer
    Add-LogLine 'Quick Transfer ON: store (no compression), split @ 250 MB, transfer instantly, NO hashing, NO verify - fastest throughput.' 'WARN'
}

# ----------------------------------------------------------------------------
# Transfer identifier: CMS case (validated) and/or OP name (UPPERCASE) - one of
# the two is required. Pass no. is always optional and never satisfies the
# requirement on its own. The folder + archive names are built from whichever
# of the three are supplied, joined by '_' (so entering both CMS case and OP
# name uses both in the name).
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
    if (-not $caseGiven -and -not $op) {
        return [pscustomobject]@{ Ok = $false; Name = $null; Kind = ''; Reason = "Enter a CMS case (e.g. $($config.CasePrefix)12345) or an OP name (UPPERCASE). A pass number alone is not enough." }
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
    $isSplit = [int]$config.VolumeSizeMB -gt 0
    $split = if ($isSplit) { "Split: $([int]$config.VolumeSizeMB) MB" } else { 'Split: off' }
    # A split archive always forces native 7z, regardless of the configured
    # format - show the format that will actually be used, not the setting.
    $fmt   = if ($isSplit) { '7z (forced by split)' } else { $config.ArchiveFormat }
    $xfer  = if (-not $isSplit) { '' } elseif ($config.TransferMode -eq 'Instant') { '  Xfer:instant' } else { '  Xfer:on-complete' }
    $hash  = if ($config.EmbedManifest) { "Hash:$($config.HashAlgorithms -join '+')" } else { 'Hash:OFF' }
    $vfy   = if ($config.VerifyAfterTransfer) { 'Verify:on' } else { 'Verify:off' }
    $ctrl.LblDest.Text = "Dest: $($config.NetworkShare)   |   7-Zip: $sz   |   $fmt  L$($config.CompressionLevel)  $split$xfer  $hash  $vfy"
}

# ----------------------------------------------------------------------------
# Transfer-in-progress popup (modeless, mirrors the live events)
# ----------------------------------------------------------------------------
function Show-ProgressWindow {
    param([string]$Name)
    Close-ProgressWindow
    $tc = $script:ThemeColors
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Transfer in progress" Height="560" Width="820" WindowStartupLocation="CenterOwner"
        Background="$($tc.WindowBg)" FontFamily="Segoe UI">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0">
      <TextBlock x:Name="PTitle" Text="Transfer in progress" FontSize="18" FontWeight="Bold" Foreground="$($tc.Accent)"/>
      <TextBlock x:Name="PStatus" Text="Starting..." Foreground="$($tc.Muted)" Margin="0,2,0,8"/>
    </StackPanel>
    <StackPanel Grid.Row="1">
      <TextBlock x:Name="PStage" Text="Preparing..." Foreground="$($tc.Text)"/>
      <ProgressBar x:Name="PBarJob" Height="16" Minimum="0" Maximum="100" Foreground="#FF66BB6A" Background="$($tc.InputBg)" Margin="0,4,0,8"/>
    </StackPanel>
    <StackPanel Grid.Row="2">
      <TextBlock x:Name="PXfer" Text="Transfer: idle" Foreground="$($tc.Text)"/>
      <ProgressBar x:Name="PBarXfer" Height="12" Foreground="$($tc.Accent)" Background="$($tc.InputBg)" Margin="0,4,0,2"/>
      <TextBlock x:Name="PCount" Text="0 file(s) transferred" Foreground="$($tc.Muted)" Margin="0,0,0,8"/>
    </StackPanel>
    <Border Grid.Row="3" Background="$($tc.LogBg)" CornerRadius="6">
      <RichTextBox x:Name="PLog" Background="Transparent" Foreground="$($tc.Text)" BorderThickness="0"
                   FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    </Border>
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
      <Button x:Name="PDelete" Content="Delete Local Copies" Padding="14,7" Margin="4" Background="#FF8E2A2A" Foreground="#FFECECEC" Visibility="Collapsed"/>
      <Button x:Name="PCancel" Content="Cancel Transfer" Padding="14,7" Margin="4" Background="#FF8E2A2A" Foreground="#FFECECEC"/>
      <Button x:Name="PClose"  Content="Close" Padding="14,7" Margin="4" Background="$($tc.ButtonBg)" Foreground="$($tc.Text)"/>
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
        Delete = (& $g 'PDelete')
    }
    (& $g 'PTitle').Text  = "Transfer in progress - $Name"
    (& $g 'PStatus').Text = "Capturing $Name..."
    (& $g 'PCount').Text  = '0 file(s) transferred'
    (& $g 'PCancel').Add_Click({ Stop-Capture })
    (& $g 'PClose').Add_Click({ Close-ProgressWindow })
    (& $g 'PDelete').Add_Click({ Remove-LocalCopies -Staging $script:LastJobStaging })
    $pw.Add_Closing({ $script:Prog = $null })
    $pw.Show()
}

function Show-A4950CompletionMessage {
    <#
    .SYNOPSIS On-screen summary shown when a transfer job finishes.
    .DESCRIPTION
        Only called for a real completion (full success or partial success
        with some failures) - not for a cancelled or hard-errored job, where
        Source/Destination/stats are either unset or not meaningful.
    #>
    param($Data, [string]$Outcome)
    $started  = if ($Data.Started)  { $Data.Started.ToString('yyyy-MM-dd HH:mm:ss') } else { 'n/a' }
    $finished = if ($Data.Finished) { $Data.Finished.ToString('yyyy-MM-dd HH:mm:ss') } else { 'n/a' }
    $lines = @(
        "Status        : $Outcome"
        ""
        "Source        : $($Data.Source)"
        "Destination   : $($Data.Destination)"
        ""
        "Started       : $started"
        "Finished      : $finished"
        ""
        "Files         : $($Data.FileCount)"
        "Folders       : $($Data.FolderCount)"
        "Original size : $(Format-A4950Bytes $Data.TotalBytes)"
        "Zipped size   : $(Format-A4950Bytes $Data.CompressedBytes)"
    ) -join "`r`n"
    [System.Windows.MessageBox]::Show($window, $lines, 'Transfer complete', 'OK', 'Information') | Out-Null
}

function Remove-LocalCopies {
    <#
    .SYNOPSIS Confirm-then-delete the local staging copies for the last completed job.
    #>
    param([string]$Staging)
    if (-not $Staging -or -not (Test-Path -LiteralPath $Staging)) {
        Add-LogLine 'Nothing to delete - local staging folder not found (already removed?).' 'WARN'
        return
    }
    $confirm = [System.Windows.MessageBox]::Show(
        "Confirm the transferred file(s) have reached their destination (High Side) " +
        "before deleting the local copies in:`n`n$Staging`n`nThis cannot be undone. Delete now?",
        'Confirm delete - local copies', 'YesNo', 'Warning')
    if ($confirm -ne 'Yes') { Add-LogLine 'Delete Local Copies cancelled by operator.' 'INFO'; return }
    try {
        Remove-Item -LiteralPath $Staging -Recurse -Force
        Add-LogLine "Local copies deleted: $Staging" 'OK'
        if ($script:Prog -and $script:Prog.Delete) {
            $script:Prog.Delete.IsEnabled = $false
            $script:Prog.Delete.Content = 'Deleted'
        }
        $script:LastJobStaging = $null
    } catch {
        Add-LogLine "Could not delete local copies: $($_.Exception.Message)" 'ERROR'
        [System.Windows.MessageBox]::Show("Could not delete the local copies:`n$($_.Exception.Message)", 'Delete failed', 'OK', 'Error') | Out-Null
    }
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

function Hide-OptionsPanel {
    if ($script:OptionsVisible) { Toggle-OptionsPanel }
}

# ----------------------------------------------------------------------------
# Slow Machine Mode: for old/low-spec hardware. Stops the System Monitor
# polling outright (rather than just slowing it) and forces single-threaded,
# low-level 7-Zip compression, trading speed for a small, predictable
# CPU/RAM footprint. Hashing and verification are untouched - integrity
# never gets weakened for the sake of resource usage.
# ----------------------------------------------------------------------------
function Set-SlowMachineMode {
    param([bool]$On)
    $script:SlowMachineMode = $On
    $config.SlowMachineMode = $On
    if ($On) {
        $statsTimer.Stop()
        $ctrl.PanelSysMonitor.Visibility = 'Collapsed'
        $ctrl.LblSlowMachineNote.Visibility = 'Visible'
        $pumpTimer.Interval = [TimeSpan]::FromMilliseconds(600)
        $usbTimer.Interval  = [TimeSpan]::FromMilliseconds(2000)
        $ctrl.BtnSlowMachine.Content = 'Slow Machine: ON'
        $ctrl.BtnSlowMachine.Background = '#FF2E7D32'
        Add-LogLine 'Slow Machine Mode ON: System Monitor stopped; compression forced to single-threaded, store (no compression math).' 'WARN'
    } else {
        $ctrl.PanelSysMonitor.Visibility = 'Visible'
        $ctrl.LblSlowMachineNote.Visibility = 'Collapsed'
        $statsTimer.Start()
        $pumpTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $usbTimer.Interval  = [TimeSpan]::FromMilliseconds(800)
        $ctrl.BtnSlowMachine.Content = 'Slow Machine: OFF'
        $ctrl.BtnSlowMachine.Background = '#FF3A3A46'
        Add-LogLine 'Slow Machine Mode OFF: System Monitor and normal multi-threaded compression restored.' 'INFO'
    }
}

# ----------------------------------------------------------------------------
# Start / cancel the capture job
# ----------------------------------------------------------------------------
# Local staging space guide (non-blocking - never prompts, never checks the
# destination). The destination is deliberately NOT probed here: over a slow
# link that round-trip adds real latency before a job can even start, for a
# number that's only ever advisory anyway - parts stream out to the
# destination as soon as each is written, so the job was never going to need
# the destination to hold the whole archive at once. Local staging is the
# one place a job can concretely fail to even START (7-Zip can't write more
# than the drive has room for), but even that is only ever a heads-up: a
# shortfall is logged and the job proceeds automatically either way.
# ----------------------------------------------------------------------------
function Get-StagingSpaceGuide {
    <#
    .SYNOPSIS Non-blocking estimate: source size vs. local staging free space.
    .OUTPUTS A note string describing the estimate (for the confirm summary / log).
    #>
    param([string[]]$Items)

    $prevCursor = $window.Cursor
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    Add-LogLine 'Estimating source size for the staging space guide...' 'INFO'
    $srcBytes = 0L
    foreach ($it in $Items) { $srcBytes += [int64](Get-A4950PathSizeBytes -Path $it) }
    $window.Cursor = $prevCursor

    $stagingPath = Expand-A4950Path $config.StagingFolder
    $free  = Get-A4950FreeSpace -Path $stagingPath
    $ratio = Get-A4950CompressionRatio -Level ([int]$config.CompressionLevel) -Format $config.ArchiveFormat
    $estBytes = [int64]($srcBytes * $ratio * 1.02)
    $note = "Estimated size to send  : $(Format-A4950Bytes $estBytes)  (source: $(Format-A4950Bytes $srcBytes), $($config.ArchiveFormat) level $($config.CompressionLevel))"

    if (-not $free.Ok) {
        Add-LogLine "Could not determine local staging free space ($stagingPath): $($free.Error). Continuing." 'WARN'
        return $note
    }

    $note += "`nLocal staging free space : $(Format-A4950Bytes $free.FreeBytes)"
    $safeFree = [int64]($free.FreeBytes * 0.95)   # 5% safety margin - advisory only
    if ($estBytes -ge $safeFree) {
        Add-LogLine ("Staging space guide: estimated ~$(Format-A4950Bytes $estBytes) may exceed local staging " +
            "free space ($(Format-A4950Bytes $free.FreeBytes)). Continuing anyway - this is a guide, not a " +
            "gate, and parts transfer out as soon as each is written.") 'WARN'
    } else {
        Add-LogLine "Staging space guide OK: ~$(Format-A4950Bytes $estBytes) estimated, $(Format-A4950Bytes $free.FreeBytes) free." 'OK'
    }
    return $note
}

function Start-Capture {
    param([switch]$NoConfirm)
    if ($script:Shared.Running) {
        # -NoConfirm calls (queue auto-advance) already check this themselves
        # before calling in, so this only ever fires for a manual click while
        # a job - queued or not - is already running.
        if (-not $NoConfirm) { Add-LogLine 'A job is already running - wait for it to finish, or Cancel it, before starting another.' 'WARN' }
        return
    }

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

    $items = Get-SelectedItemPaths
    if ($items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one folder or file to capture.', 'Nothing selected', 'OK', 'Warning') | Out-Null
        return
    }

    $caseSafe = New-A4950CaseFolderName $name

    # Pre-flight: a non-blocking guide only - local staging space vs. estimated
    # size. Never checks the destination (slow-link latency for no benefit)
    # and never stops the job; a shortfall is just logged as a warning.
    $spaceNote = Get-StagingSpaceGuide -Items $items

    if (-not $NoConfirm) {
        # List each selected item's FULL source path, the destination folder and the
        # single combined archive name.
        $isSplit = [int]$config.VolumeSizeMB -gt 0
        # A split archive always ends up native 7z, regardless of the configured
        # format - 7-Zip's -v switch doesn't split zip, and only a genuine 7z
        # volume set gives a receiving tool a verifiable volume count.
        $fmt = if ($isSplit) { '7z' } else { $config.ArchiveFormat }
        $xferDesc = if ($config.TransferMode -eq 'Instant') { 'transferred instantly, as each finishes' } else { 'transferred once the whole archive is complete' }
        $splitSuffix = if ($isSplit) { ".001, .002, ... (split forces 7z format; volumes $xferDesc)" } else { '' }
        $lines = foreach ($it in $items) { "   SOURCE: $it" }
        $maxShow = 15
        $shown = @($lines | Select-Object -First $maxShow)
        if ($items.Count -gt $maxShow) { $shown += "   ... and $($items.Count - $maxShow) more" }
        $archiveNote = "COMBINED into ONE archive - ${caseSafe}_<timestamp>.$fmt$splitSuffix (unique name, no destination sub-folder)`n`nSelected items (full source path):`n$($shown -join "`n")"
        $destPath = $config.NetworkShare
        $driveRoot = Get-SelectedDriveRoot
        $srcRootFull = if ($driveRoot) { "$driveRoot\" } else { '(manually added items - see full paths below)' }
        $integrity = if ($config.EmbedManifest) {
            "Originals will be hashed ($($config.HashAlgorithms -join ' + '))" +
            $(if ($config.VerifyAfterTransfer) { ' and verified at the destination' } else { ' (no destination verify)' }) + '.'
        } else {
            "WARNING: Quick Transfer - NO hashing and NO verification. File integrity will not be recorded."
        }
        $msg = @"
Capture $($items.Count) selected item(s) as '$name' ($($tn.Kind))?

$spaceNote

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
    Play-A4950StartSound
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
# 3s rather than 1.5s: the System Monitor panel is a coarse indicator, not a
# live meter, and this halves the CPU spent polling WMI/CIM for it.
$statsTimer.Interval = [TimeSpan]::FromMilliseconds(3000)
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
                elseif ($m.Fail) { Add-LogLine "Job finished: $($m.Ok) transferred, $($m.Fail) failed. -> $($m.Destination)" 'WARN'; $ctrl.LblXfer.Text = "Complete ($($m.Ok) transferred)"; $endText = "Complete - $($m.Ok) transferred, $($m.Fail) failed"; Play-A4950ErrorSound; Show-A4950CompletionMessage -Data $m -Outcome $endText }
                else { Add-LogLine "Job finished: $($m.Ok) transferred, $($m.Fail) failed. -> $($m.Destination)" 'OK'; $ctrl.LblXfer.Text = "Complete ($($m.Ok) transferred)"; $endText = "Complete - $($m.Ok) transferred, $($m.Fail) failed"; Play-A4950CompletedSound; Show-A4950CompletionMessage -Data $m -Outcome $endText }
                if ($m.Destination -and $m.Files -and @($m.Files).Count -gt 0) {
                    Add-LogLine "Destination: $($m.Destination)" 'STEP'
                    foreach ($fn in @($m.Files)) { Add-LogLine "  -> $fn" 'OK' }
                }
                $ctrl.LblStage.Text = 'No job running'; $ctrl.BarJob.IsIndeterminate = $false; $ctrl.BarJob.Value = 0; $ctrl.LblJob.Text = ''
                $ctrl.BarXfer.IsIndeterminate = $false; $ctrl.BarXfer.Value = 0
                $script:LastJobStaging = if ($m.Staging) { $m.Staging } else { $null }
                if ($P) {
                    $P.Status.Text = if ($m.Destination) { "$endText   |   Destination: $($m.Destination)" } else { $endText }
                    $P.Title.Text = 'Transfer finished'
                    $P.Stage.Text = 'Done'; $P.BarJob.IsIndeterminate = $false; $P.BarJob.Value = 0
                    $P.BarXfer.IsIndeterminate = $false; $P.BarXfer.Value = 0
                    $P.Cancel.IsEnabled = $false
                    if ($script:LastJobStaging) {
                        $P.Delete.Visibility = 'Visible'; $P.Delete.IsEnabled = $true; $P.Delete.Content = 'Delete Local Copies'
                    }
                }
                Complete-Capture
                if ($script:QueueRunning) { Start-NextQueuedJob }   # auto-advance to the next queued job, if any
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
        Update-DriveList -Prefer $drive
        # "Select all folders/files by default" now means: add the whole
        # drive as one folder entry (captured recursively, in full, at
        # capture time) - the flat-list equivalent of the old tree opening
        # fully checked. Otherwise nothing is added automatically; use
        # Browse Folders.../Add Files... to build the selection.
        $selectAllDefault = if ($ctrl.OptSelDefault) { [bool]$ctrl.OptSelDefault.IsChecked } else { [bool]$config.DefaultSelectAll }
        if ($selectAllDefault) {
            if (Add-SelectedItem -Path "$drive\" -IsFolder $true) {
                Add-LogLine "USB drive connected: $drive - added to selection (Select all by default)." 'STEP'
            } else {
                Add-LogLine "USB drive connected: $drive - already in the selection." 'STEP'
            }
        } else {
            Add-LogLine "USB drive connected: $drive - use Browse Folders.../Add Files... to add items." 'STEP'
        }
        $ctrl.StatusLine.Text = "USB drive $drive connected and scanned."
        if ($script:Shared.Running) { continue }

        if ($ctrl.OptPrompt.IsChecked) {
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
  1. Build the selection using "Browse Folders..." (standard Windows folder
     picker - pick one folder at a time, then choose "Yes" to add another;
     each one's sub-folders and files are included automatically) and
     "Add Files..." (multi-select file picker, for individual files). Both
     add to the list rather than replacing it. Remove an item with its own
     "Remove" button, or clear everything with "Clear Selection". Picking a
     drive from the "Source drive" dropdown also opens a folder browser
     rooted at that drive - useful for local drives and external HDDs too,
     not just USB sticks.
     If "Select all folders/files by default" is on in Options, plugging in
     a USB drive adds the whole drive to the selection automatically.
  2. Fill in a CMS case (starts with '$($config.CasePrefix)') and/or an OP NAME
     (UPPERCASE) - at least one of these two is required. PASS NUMBER is
     always optional. Whatever you provide is combined into the folder/file
     name (e.g. $($config.CasePrefix)12345_JBLOGGS_PASS4471) - if both CMS case
     and OP name are entered, both are used.
  3. Press "Start Capture" and confirm the summary (which lists the folders, the
     destination and the zip names) - or press "Add to Queue" to queue this
     job and build another one instead of starting immediately; see JOB
     QUEUE below.
  4. When the job finishes, the Activity Log (and the transfer-finished popup)
     shows the destination path and the name of every file written there.

SLOW MACHINE MODE
  Click "Slow Machine: OFF" in the header to turn it ON for an old or
  low-spec machine. It stops the System Monitor's polling outright (rather
  than just slowing it down) and forces single-threaded, store-only (no
  compression math) 7-Zip, regardless of the Level/format set in Options -
  trading speed and archive size for the smallest possible CPU/RAM load.
  Hashing, the manifest and verification are unaffected.

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

JOB QUEUE
  Line up several capture jobs to run one after another, unattended, instead
  of starting each one by hand:
  1. Build a selection and enter a CMS case/OP/pass as normal, then click
     "Add to Queue" instead of "Start Capture". This snapshots the current
     selection, identifiers AND every Options setting into a queue entry -
     later changes to Options can never retroactively change an already-
     queued job - then clears the screen so you can build the next one.
  2. Click "Start Queue" once you've queued everything. Jobs run one at a
     time, in the order queued; as soon as one finishes, the next one starts
     automatically - no need to click anything in between.
  3. Each queued job has its own "Edit" and "Remove" buttons:
       - "Remove" cancels that queued job outright - it's gone, nothing
         about it will ever run.
       - "Edit" pulls it back out of the queue onto the main screen (its
         selection, identifiers and Options are all reloaded) so you can
         change anything, then either "Start Capture" it immediately or
         "Add to Queue" again.
  4. "Stop Queue" stops the AUTO-ADVANCE only - whatever job is currently
     running keeps running (or use "Cancel" for that, same as any other
     job) - it just means nothing further starts automatically once it's
     done. Click "Start Queue" again later to resume from wherever the
     queue was left.
  A job already running (queued or started by hand) still blocks a second
  one from starting at the same time - this tool runs one capture job at a
  time, queued jobs just take turns automatically rather than needing a
  click each time.

STAGING SPACE GUIDE
  Before starting, the tool estimates the source size and logs it against the
  LOCAL STAGING folder's free space - never the destination, so a slow link
  never adds delay to starting a job. This is a non-blocking guide, not a
  gate: if it looks tight, a warning is logged and the job proceeds anyway,
  automatically, with no prompt. It's a planning ESTIMATE, not a guarantee -
  already-compressed data (photos/video/zips) shrinks far less than typical
  documents.

TEMP CLEANUP
  Local copies (the zip/7z file(s), manifest and transfer log) are ALWAYS
  kept in the staging folder after a completed job - nothing is deleted
  automatically. Once you've confirmed the files reached their destination,
  remove them either manually or with "Delete Local Copies" on the transfer
  -finished window, which prompts you to confirm first. (A cancelled job's
  partial output IS still cleaned up automatically, since it has no
  evidentiary value.)

COMBINED ARCHIVE
  All selected folders/files are always packed into ONE combined archive (this
  is not configurable) - one manifest covers every selected item, with each
  file's entry prefixed by its original top-level folder name so nothing
  collides.

TRANSFER ORDER
  Set in Options under "ARCHIVE VOLUME TRANSFER" (only matters when split):
    - "Wait for All Files" (default, safest): 7-Zip is a black box while
      running, so every volume is picked up for transfer together, only
      once the whole process has exited and every volume is confirmed
      complete.
    - "Transfer Immediately": each volume is picked up for transfer the
      moment 7-Zip finishes writing it - not once the whole archive is done.
  EITHER way, EXCEPT .001: it's always held back and sent only once every
  other volume has already been queued - even in Instant mode, since 7-Zip
  itself only finalises .001 at the very end of the run regardless (the
  archive's start header can only be written once the whole body is known).
  Since the set can't be reassembled/opened without .001, this means an
  incomplete transfer at the destination can never look like a finished one.

OPTIONS (all on the main screen, right-hand panel)
  Network share, 7-Zip path, staging folder, case prefix, archive format,
  volume/split size, archive volume transfer mode, compression level,
  password, hashing, manifest embedding, verification, prompt-on-insert,
  select-all default, delete-local and exclude patterns. Every option can be
  toggled/edited and "Save Options" persists them to config.json. Options
  also apply immediately when you press Start.

WHAT HAPPENS
  - Every original file across your whole selection is hashed (SHA-256 / MD5)
    into one manifest.
  - Everything selected is compressed with 7-Zip into ONE archive; the
    manifest is embedded.
  - Large archives are split into volumes ($([int]$config.VolumeSizeMB) MB each by default) so no
    single file is unwieldy. Set the size to 0 for one file. A split ALWAYS
    uses native 7z volumes, regardless of the archive format configured -
    7-Zip's -v switch silently does not split .zip, and a home-rolled byte
    split would not be reliably verifiable by a receiving tool the way
    7-Zip's own volumes are (see NAMING below).
  - Volumes transfer per the "Archive volume transfer" setting above - see
    TRANSFER ORDER.
  - Optionally the transferred archive is re-hashed at the destination to verify.

NAMING
  Files land directly in the destination - NO per-case sub-folder. The
  archive name is built from the CMS case and/or OP name, plus pass number if
  given, plus this job's own timestamp, so two jobs never collide there:
    <share>\$($config.CasePrefix)12345_20260818_143000.$($config.ArchiveFormat)   (unsplit)
    <share>\$($config.CasePrefix)12345_20260818_143000.7z.001, .7z.002, ...       (split)
  When split, volumes are always native 7z (regardless of archive format) -
  open the .001 in 7-Zip to reassemble (keep all parts together), or
  "7z x <name>.7z.001" from the command line. Plain copy/cat concatenation
  does NOT work for these - a genuine 7z volume set is what lets 7-Zip
  itself refuse to report a volume count, or open at all, until every part
  is truly present; a plain byte-split file can't offer that guarantee. If
  recipients without 7-Zip need to open a delivery directly, keep it unsplit.
  The manifest and transfer log sent to the destination use the same unique
  name.

SYSTEM MONITOR
  Live CPU, memory, network throughput and temp-folder free space.

HIDE OPTIONS
  Click "Hide Options" in the header to collapse the Options panel and give
  the Activity Log more room; click "Show Options" to bring it back. Your
  settings are unaffected either way - it only changes what's on screen.

NOTIFICATION SOUNDS
  Set in Options under "SOUNDS": pick a .wav file for the start, finish and
  error events, or leave any of them blank to use a standard Windows sound
  instead (Beep on start, Asterisk on finish, Hand/Critical Stop on error).
  If a configured .wav can't be played (missing, moved, unsupported format),
  the standard Windows sound plays instead for that event and a warning is
  logged.

TRANSFER LOG & COMPLETION SUMMARY
  Every completed job's Activity Log, worker log and TRANSFER.log now record
  the start time, finish time, number of files, number of folders, the
  original (uncompressed) total size and the compressed ("zipped") size that
  was actually written to the destination. When a job finishes (success or
  partial failure), an on-screen summary also pops up showing the Source and
  Destination locations alongside all of the above.

APPEARANCE
  Set in Options under "APPEARANCE":
    - "Text size": Small / Medium / Large / Extra Large - scales all text in
      the app immediately, no restart or Save Options needed.
    - "Dark Mode": on by default; untick for a light theme. Also applies
      immediately.

See README.md and docs\USER_GUIDE.md for full documentation.
"@
    [System.Windows.MessageBox]::Show($msg, 'Help', 'OK', 'Information') | Out-Null
}

# ----------------------------------------------------------------------------
# Wire up events
# ----------------------------------------------------------------------------
$ctrl.BtnRefresh.Add_Click({ Update-DriveList; Add-LogLine 'Drives rescanned.' 'INFO' })
$ctrl.BtnToggleOptions.Add_Click({ Toggle-OptionsPanel })
$ctrl.BtnSlowMachine.Add_Click({ Set-SlowMachineMode -On (-not $script:SlowMachineMode) })
$ctrl.BtnDriveRefresh.Add_Click({ Update-DriveList; Add-LogLine 'Drives refreshed.' 'INFO' })
$ctrl.CmbDrive.Add_SelectionChanged({
    # Only react to the operator manually picking a drive - not to
    # Update-DriveList setting the list/selection programmatically (startup,
    # Rescan/Refresh Drives, USB insert).
    if ($script:SuppressDriveBrowse) { return }
    $root = Get-SelectedDriveRoot
    if (-not $root) { return }
    $picked = Select-Folder -Description "Select a folder or sub-folder on $root to add (all sub-folders and files are included)" -Start "$root\"
    if (-not $picked) { return }
    if (Add-SelectedItem -Path $picked -IsFolder $true) { Add-LogLine "Added from ${root}: $picked" 'OK' }
    else { Add-LogLine "Folder already in the selection: $picked" 'WARN' }
})
$ctrl.BtnBrowseFolder.Add_Click({ Add-BrowsedFolder })
$ctrl.BtnBrowseFiles.Add_Click({ Add-BrowsedFiles })
$ctrl.BtnHelp.Add_Click({ Show-Help })
$ctrl.BtnQuick.Add_Click({ Set-QuickTransfer })
$ctrl.BtnStart.Add_Click({ Start-Capture })
$ctrl.BtnCancel.Add_Click({ Stop-Capture })
$ctrl.BtnAddQueue.Add_Click({ Add-ToQueue })
$ctrl.BtnStartQueue.Add_Click({ Start-JobQueue })
$ctrl.BtnStopQueue.Add_Click({ Stop-JobQueue })
$ctrl.BtnClearSelection.Add_Click({ Clear-Selection })
$ctrl.BtnSaveOptions.Add_Click({ Save-Options })
$ctrl.BtnBrowseNet.Add_Click({ $p = Select-Folder 'Select the destination folder (UNC share or local path)' $ctrl.OptNet.Text; if ($p) { $ctrl.OptNet.Text = $p } })
$ctrl.BtnBrowseStage.Add_Click({ $p = Select-Folder 'Select the local staging folder' (Expand-A4950Path $ctrl.OptStage.Text); if ($p) { $ctrl.OptStage.Text = $p } })
$ctrl.BtnBrowse7z.Add_Click({ $p = Select-SevenZipFile; if ($p) { $ctrl.Opt7z.Text = $p } })
$ctrl.BtnBrowseSoundStart.Add_Click({ $p = Select-WavFile -Title 'Select start sound (.wav)'; if ($p) { $ctrl.OptSoundStart.Text = $p } })
$ctrl.BtnBrowseSoundFinish.Add_Click({ $p = Select-WavFile -Title 'Select finish sound (.wav)'; if ($p) { $ctrl.OptSoundFinish.Text = $p } })
$ctrl.BtnBrowseSoundError.Add_Click({ $p = Select-WavFile -Title 'Select error sound (.wav)'; if ($p) { $ctrl.OptSoundError.Text = $p } })
$ctrl.OptDarkMode.Add_Click({ Set-A4950Theme -Dark ([bool]$ctrl.OptDarkMode.IsChecked) })
$ctrl.OptFontSize.Add_SelectionChanged({ if ($ctrl.OptFontSize.SelectedItem) { Set-A4950FontScale -Size $ctrl.OptFontSize.SelectedItem.Tag } })
$ctrl.OptLevel.Add_ValueChanged({ $ctrl.OptLevelLbl.Text = "Compression level: $([int]$ctrl.OptLevel.Value)" })
$ctrl.OptFormat.Add_SelectionChanged({ if ($ctrl.OptFormat.SelectedItem) { $config.ArchiveFormat = $ctrl.OptFormat.SelectedItem.Content; Update-NamePreview } })
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
    try {
        $ctrl.LblVersion.Text = "v$script:AppVersion"
        $window.Title = "Auto 49/50 v$script:AppVersion - USB Compression & Transfer Tool"
        Set-OptionsFromConfig
        Set-A4950Theme -Dark ([bool]$config.DarkMode)
        Set-A4950FontScale -Size ([string]$config.FontSize)
        Update-DriveList
        Update-SelectionCount
        Update-Footer
        Update-NamePreview
        Register-UsbWatcher
        $pumpTimer.Start(); $usbTimer.Start()
        Set-SlowMachineMode -On ([bool]$config.SlowMachineMode)   # also starts/skips statsTimer as appropriate
        Add-LogLine "Auto 49/50 v$script:AppVersion ready." 'OK'
        if (-not (Resolve-SevenZip -PreferredPath $config.SevenZipPath)) {
            Add-LogLine '7-Zip not found. Install it (https://www.7-zip.org) or set the 7-Zip path in Options.' 'ERROR'
        }
    } catch {
        # Startup failures happen before the Activity Log can be trusted to
        # show anything (the failure could be in the log/theme plumbing
        # itself), so surface this with a hard MessageBox rather than
        # risking a silent crash with no visible error at all.
        [System.Windows.MessageBox]::Show(
            "Auto 49/50 failed to start up correctly:`n`n$($_.Exception.GetType().Name): $($_.Exception.Message)`n`n$($_.ScriptStackTrace)",
            'Startup error', 'OK', 'Error') | Out-Null
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
