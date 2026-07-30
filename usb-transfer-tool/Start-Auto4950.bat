@echo off
rem ============================================================================
rem  Auto 49/50 - USB Compression & Transfer Tool  (launcher)
rem  Starts the GUI with the execution policy bypassed for this process only,
rem  so you don't have to change any system settings. Nothing is changed
rem  permanently on the machine.
rem ============================================================================
setlocal
cd /d "%~dp0"

rem -NoProfile  : ignore the user's PowerShell profile (faster, predictable)
rem -ExecutionPolicy Bypass : allow this unsigned script to run (this process only)
rem -STA        : WPF requires a single-threaded apartment
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Start-Auto4950.ps1"

if errorlevel 1 (
  echo.
  echo Auto 49/50 exited with an error. Review the messages above.
  pause
)
endlocal
