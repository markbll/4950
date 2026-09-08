<#
.SYNOPSIS
    Auto 49/50 - one-time Windows permissions fix so the scripts can run.

.DESCRIPTION
    Windows blocks unsigned PowerShell scripts two separate ways, and both
    need clearing before Setup.ps1 / Start-Auto4950.ps1 can be launched by
    double-click or "Run with PowerShell" (the .bat launchers already work
    regardless, since they pass -ExecutionPolicy Bypass for that one process
    only):

      1. Mark of the Web - Windows 11 tags every file extracted from a
         downloaded .zip as "this came from the internet" (a hidden
         Zone.Identifier stream). PowerShell treats that as untrusted even
         under a RemoteSigned execution policy. This unblocks every script
         file in this folder (and Modules\) so that flag is cleared.
      2. Execution policy - Windows' default ('Restricted' on client
         editions) blocks ALL unsigned local scripts outright, unblocked or
         not. This offers to set 'RemoteSigned' for your user account only
         (no administrator rights needed, and it doesn't change the policy
         for anyone else on the machine).

    Safe to re-run any time - both fixes are idempotent.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Fix-Permissions.ps1
#>

[CmdletBinding()]
param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Auto 49/50 - Permissions Setup" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# 1) Unblock every script file - clears the "downloaded from the internet"
#    Mark-of-the-Web flag Windows adds when extracting a .zip.
# ----------------------------------------------------------------------------
Write-Host "Unblocking script files in $scriptRoot ..."
$files = Get-ChildItem -LiteralPath $scriptRoot -Recurse -Include '*.ps1', '*.psm1', '*.bat' -File -ErrorAction SilentlyContinue
$unblocked = 0
foreach ($f in $files) {
    try {
        Unblock-File -LiteralPath $f.FullName -ErrorAction Stop
        $unblocked++
    } catch {
        Write-Warning "Could not unblock $($f.Name): $($_.Exception.Message)"
    }
}
Write-Host "  $unblocked file(s) checked/unblocked." -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------------------
# 2) Execution policy - offer to set RemoteSigned for the current user only.
# ----------------------------------------------------------------------------
Write-Host "Checking PowerShell execution policy..."
$permissive = @('RemoteSigned', 'Unrestricted', 'Bypass')
$effective = Get-ExecutionPolicy

if ($effective -in $permissive) {
    Write-Host "  Already '$effective' - no change needed." -ForegroundColor Green
} else {
    # If Group Policy is forcing the policy, CurrentUser cannot override it.
    $machinePolicy = Get-ExecutionPolicy -Scope MachinePolicy
    $userPolicy    = Get-ExecutionPolicy -Scope UserPolicy
    if ($machinePolicy -ne 'Undefined' -or $userPolicy -ne 'Undefined') {
        Write-Host "  Policy is '$effective', enforced by Group Policy (Machine='$machinePolicy', User='$userPolicy')." -ForegroundColor Yellow
        Write-Host "  A local override isn't possible. Either ask your administrator to allow" -ForegroundColor Yellow
        Write-Host "  'RemoteSigned', or always launch via the .bat files, or run:" -ForegroundColor Yellow
        Write-Host "      powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1" -ForegroundColor Yellow
    } else {
        Write-Host "  Current policy: '$effective' - this blocks unsigned scripts like these." -ForegroundColor Yellow
        $answer = Read-Host "  Set it to 'RemoteSigned' for your user account now? (no admin rights needed) [Y/n]"
        if ($answer -eq '' -or $answer -match '^(y|yes)$') {
            try {
                Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
                Write-Host "  Done. Execution policy for your account is now 'RemoteSigned'." -ForegroundColor Green
            } catch {
                Write-Warning "  Couldn't change the policy automatically: $($_.Exception.Message)"
                Write-Host "  Run this once in a PowerShell window, then try again:" -ForegroundColor Yellow
                Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Skipped. You can always launch via the .bat files instead, or run:" -ForegroundColor Yellow
            Write-Host "      powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Done. You can now run Setup.ps1 and Start-Auto4950.ps1 - by double-clicking" -ForegroundColor Cyan
Write-Host "their .bat launchers, or by right-clicking the .ps1 files and choosing" -ForegroundColor Cyan
Write-Host "'Run with PowerShell'." -ForegroundColor Cyan
