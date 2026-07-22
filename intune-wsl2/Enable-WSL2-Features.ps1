<#
.SYNOPSIS
    Enables the Windows optional features WSL 2 depends on, and sets the
    machine-wide default WSL version to 2.

.DESCRIPTION
    Intended as a PRE-INSTALL SCRIPT attached to the Patch My PC catalog app
    "Windows Subsystem for Linux (MSI-x64)".

    The catalog app installs and keeps the WSL MSI up to date, but it does not
    enable the Windows optional features that WSL 2 requires, and it does not
    set the default WSL version. This script covers that gap:

      - VirtualMachinePlatform            (required for WSL 2)
      - Microsoft-Windows-Subsystem-Linux (enabled for compatibility)
      - HKLM ...\Lxss\DefaultVersion = 2  (machine-wide, unlike the per-user
                                           "wsl --set-default-version 2")

    It deliberately does NOT download or install the WSL MSI - that is the
    catalog app's job.

.NOTES
    Exit codes:
        0    = success, prerequisites already active
        3010 = success, reboot required before WSL 2 will function
        1    = failure

    PMPC pre-install scripts treat BOTH 0 and 3010 as success, so returning
    3010 is safe: it does not abort the install that follows, and it records
    the pending-reboot state accurately. It does not by itself guarantee the
    device restarts before a dependent app installs - configure the restart
    behaviour on the DEPLOYMENT as well. See PMPC-Cloud-Setup.md.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Enable-WSL2-Features.log
#>

#region --- Relaunch as 64-bit if running under a 32-bit host ---------------
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
    $sysNativePowerShell = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    & $sysNativePowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
#endregion

$ErrorActionPreference = 'Stop'
$logDir = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
if (-not (Test-Path $logDir)) { $logDir = $env:TEMP }
Start-Transcript -Path (Join-Path $logDir 'Enable-WSL2-Features.log') -Append -Force

$rebootRequired = $false
$exitCode = 0

try {
    Write-Output "=== WSL 2 prerequisite enablement started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
    Write-Output "Hypervisor present: $((Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent)"

    #region --- Enable required Windows optional features -------------------
    $features = @(
        'VirtualMachinePlatform',
        'Microsoft-Windows-Subsystem-Linux'
    )

    foreach ($feature in $features) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
        Write-Output "Feature '$feature' current state: $state"

        if ($state -ne 'Enabled') {
            Write-Output "Enabling feature '$feature'..."
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
            if ($result.RestartNeeded) {
                Write-Output "Feature '$feature' requires a restart."
                $rebootRequired = $true
            }
        }
    }
    #endregion

    #region --- Set machine-wide default WSL version to 2 -------------------
    $lxssKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lxssKey)) {
        New-Item -Path $lxssKey -Force | Out-Null
    }
    New-ItemProperty -Path $lxssKey -Name 'DefaultVersion' -Value 2 `
        -PropertyType DWord -Force | Out-Null
    Write-Output 'Machine-wide default WSL version set to 2.'
    #endregion

    if ($rebootRequired) {
        Write-Output 'REBOOT PENDING: features are enabled but will not be active until the device restarts.'
        Write-Output 'WSL 2 will not function, and dependent apps may fail, until that restart happens.'
        $exitCode = 3010
    }
    else {
        Write-Output 'All prerequisites already active; no restart required.'
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Write-Output "=== WSL 2 prerequisite enablement finished (reboot pending: $rebootRequired, exit $exitCode) ==="
    Stop-Transcript
}

exit $exitCode
