@echo off
rem ============================================================================
rem  Auto 49/50 - Permissions Setup  (launcher)
rem  One-time fix so Windows 11 will run these scripts: unblocks every file
rem  extracted from the download, and offers to set a per-user execution
rem  policy that allows locally-created scripts to run. No administrator
rem  rights are required, and nothing changes machine-wide.
rem ============================================================================
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-Permissions.ps1"

echo.
pause
endlocal
