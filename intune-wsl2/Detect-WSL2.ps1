<#
.SYNOPSIS
    Intune Win32 app detection script for WSL 2 enablement.

.DESCRIPTION
    Detection succeeds (exit 0 + output on STDOUT) only when ALL of the
    following are true:
      - VirtualMachinePlatform feature is Enabled
      - Microsoft-Windows-Subsystem-Linux feature is Enabled
      - The modern WSL package is installed (wsl.exe under Program Files\WSL
        or the WSLService service exists)

    Anything else exits 1 with no output, which Intune treats as
    "not detected". Features in 'EnablePending' state (reboot not yet taken)
    intentionally count as NOT detected so Intune keeps the app pending
    until the reboot completes.
#>

$ErrorActionPreference = 'SilentlyContinue'

$features = @(
    'VirtualMachinePlatform',
    'Microsoft-Windows-Subsystem-Linux'
)

foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
    if ($state -ne 'Enabled') {
        exit 1
    }
}

$wslExePresent  = Test-Path -Path (Join-Path $env:ProgramFiles 'WSL\wsl.exe')
$wslServiceHere = $null -ne (Get-Service -Name 'WSLService' -ErrorAction SilentlyContinue)

if ($wslExePresent -or $wslServiceHere) {
    Write-Output 'WSL2 fully enabled.'
    exit 0
}

exit 1
