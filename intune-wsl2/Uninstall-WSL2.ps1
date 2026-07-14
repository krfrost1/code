<#
.SYNOPSIS
    Uninstalls the WSL MSI package and disables the WSL-related Windows
    optional features. Counterpart to Install-WSL2.ps1 for Intune Win32.

.NOTES
    Exit codes: 0 = success, 3010 = success + reboot required, 1 = failure.
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Uninstall-WSL2.log

    WARNING: Disabling these features breaks anything that depends on WSL2
    (e.g. Docker Desktop). Existing WSL distros are not deleted by this
    script but will be inaccessible until WSL is re-enabled.
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
Start-Transcript -Path (Join-Path $logDir 'Uninstall-WSL2.log') -Append -Force

$rebootRequired = $false
$exitCode = 0

try {
    Write-Output "=== WSL2 removal started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

    #region --- Uninstall the WSL MSI package -------------------------------
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $wslProduct = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'Windows Subsystem for Linux' -and $_.PSChildName -like '{*}' } |
        Select-Object -First 1

    if ($wslProduct) {
        Write-Output "Uninstalling MSI product: $($wslProduct.DisplayName) $($wslProduct.DisplayVersion)"
        $msiArgs = @('/x', $wslProduct.PSChildName, '/qn', '/norestart')
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        switch ($process.ExitCode) {
            0    { Write-Output 'WSL MSI uninstalled.' }
            3010 { Write-Output 'WSL MSI uninstalled (reboot required).'; $rebootRequired = $true }
            default { throw "WSL MSI uninstall failed with exit code $($process.ExitCode)." }
        }
    }
    else {
        Write-Output 'WSL MSI package not found; skipping MSI uninstall.'
    }
    #endregion

    #region --- Disable Windows optional features ---------------------------
    $features = @(
        'Microsoft-Windows-Subsystem-Linux',
        'VirtualMachinePlatform'
    )

    foreach ($feature in $features) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
        if ($state -eq 'Enabled') {
            Write-Output "Disabling feature '$feature'..."
            $result = Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart
            if ($result.RestartNeeded) { $rebootRequired = $true }
        }
        else {
            Write-Output "Feature '$feature' already in state '$state'; skipping."
        }
    }
    #endregion

    $exitCode = if ($rebootRequired) { 3010 } else { 0 }
    Write-Output "Completed successfully (reboot required: $rebootRequired)."
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Write-Output "=== WSL2 removal finished with exit code $exitCode ==="
    Stop-Transcript
}

exit $exitCode
