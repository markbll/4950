@echo off
rem ============================================================================
rem  Auto 49/50 - Kiosk Mode  (launcher)
rem  Starts the one-button, full-screen kiosk front end with the execution
rem  policy bypassed for this process only, so nothing on the machine is
rem  changed. Uses the same config.json as the main app - set the
rem  destination, compression, hashing etc. with Setup.ps1 or the main app
rem  first.
rem ============================================================================
setlocal
cd /d "%~dp0"

rem -NoProfile  : ignore the user's PowerShell profile (faster, predictable)
rem -ExecutionPolicy Bypass : allow this unsigned script to run (this process only)
rem -STA        : WPF requires a single-threaded apartment
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Start-Auto4950-Kiosk.ps1"

if errorlevel 1 (
  echo.
  echo Auto 49/50 Kiosk Mode exited with an error. Review the messages above.
  pause
)
endlocal
