<#
.SYNOPSIS
    Enables WSL 2 completely on Windows 11 (including Windows 365 Cloud PCs).

.DESCRIPTION
    Intended for deployment as an Intune Win32 app running in SYSTEM context.

    1. Relaunches itself as 64-bit if invoked from a 32-bit host process.
    2. Enables the required Windows optional features:
         - VirtualMachinePlatform
         - Microsoft-Windows-Subsystem-Linux
    3. Installs (or updates) the Microsoft Store-independent WSL MSI package
       from the official microsoft/WSL GitHub releases. This package includes
       the WSL 2 kernel, WSLg, and wsl.exe - everything Docker Desktop needs.
       If a wsl.*.msi is placed next to this script inside the .intunewin
       package, that local copy is used instead (fully offline install).
    4. Sets the machine-wide default WSL version to 2.
    5. Exits 3010 (soft reboot required) when a restart is needed,
       otherwise 0.

.NOTES
    Exit codes:
        0    = success, no reboot needed
        3010 = success, reboot required (Intune treats as soft reboot)
        1    = failure (see log)

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-WSL2.log
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
Start-Transcript -Path (Join-Path $logDir 'Install-WSL2.log') -Append -Force

$rebootRequired = $false
$exitCode = 0

try {
    Write-Output "=== WSL2 enablement started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

    #region --- Sanity check: hypervisor / nested virtualization ------------
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-Output "Machine model: $($computerInfo.Model)"
    $hypervisorPresent = (Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent
    Write-Output "Hypervisor present: $hypervisorPresent"
    # Note: on Windows 365, 4 vCPU+ SKUs support nested virtualization by
    # default. If this is false on such a SKU, the feature enablement below
    # will still succeed but WSL2 will not start until virtualization is
    # available. We log it rather than fail, because the value can read
    # false before the features + reboot are applied.
    #endregion

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

    #region --- Install / update the WSL MSI package ------------------------
    # Prefer a locally packaged MSI (offline / no-egress environments):
    $localMsi = Get-ChildItem -Path $PSScriptRoot -Filter 'wsl*.msi' -ErrorAction SilentlyContinue |
                Select-Object -First 1

    if ($localMsi) {
        $msiPath = $localMsi.FullName
        Write-Output "Using locally packaged MSI: $msiPath"
    }
    else {
        Write-Output 'No local MSI found. Downloading latest WSL release from GitHub (microsoft/WSL)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $release = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/microsoft/WSL/releases/latest' `
            -Headers @{ 'User-Agent' = 'IntuneWSL2Installer' } `
            -UseBasicParsing

        $asset = $release.assets | Where-Object { $_.name -match '^wsl\..*x64\.msi$' } | Select-Object -First 1
        if (-not $asset) {
            throw 'Could not locate an x64 WSL MSI asset in the latest GitHub release.'
        }

        Write-Output "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)..."
        $msiPath = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -UseBasicParsing
    }

    Write-Output "Installing WSL MSI: $msiPath"
    $msiArgs = @('/i', "`"$msiPath`"", '/qn', '/norestart')
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru

    switch ($process.ExitCode) {
        0     { Write-Output 'WSL MSI installed successfully.' }
        3010  { Write-Output 'WSL MSI installed successfully (reboot required).'; $rebootRequired = $true }
        1638  { Write-Output 'A newer or same version of WSL is already installed. Continuing.' }
        default { throw "WSL MSI installation failed with exit code $($process.ExitCode)." }
    }
    #endregion

    #region --- Set machine-wide default WSL version to 2 -------------------
    # Modern WSL releases default to version 2, but we set it explicitly for
    # any user profile created after this point via the default registry hive.
    $lxssDefaultsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lxssDefaultsKey)) {
        New-Item -Path $lxssDefaultsKey -Force | Out-Null
    }
    New-ItemProperty -Path $lxssDefaultsKey -Name 'DefaultVersion' -Value 2 `
        -PropertyType DWord -Force | Out-Null
    Write-Output 'Machine-wide default WSL version set to 2.'
    #endregion

    if ($rebootRequired) {
        Write-Output 'Completed successfully. A reboot is required to finish enablement.'
        $exitCode = 3010
    }
    else {
        Write-Output 'Completed successfully. No reboot required.'
        $exitCode = 0
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Write-Output "=== WSL2 enablement finished with exit code $exitCode ==="
    Stop-Transcript
}

exit $exitCode
