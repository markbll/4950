@echo off
rem ============================================================================
rem  Auto 49/50 - Setup Wizard  (launcher)
rem  Runs the first-time configuration wizard with the execution policy
rem  bypassed for this process only. Nothing is changed permanently.
rem ============================================================================
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Setup.ps1"

if errorlevel 1 (
  echo.
  echo Setup exited with an error. Review the messages above.
  pause
)
endlocal
