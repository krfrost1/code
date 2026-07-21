# WSL 2 Enablement — Intune Win32 App

Generic, tenant-agnostic package that fully enables WSL 2 on Windows 11
(designed for Windows 365 Cloud PCs, works on physical devices too).
Purpose: satisfy the WSL 2 prerequisite so Docker Desktop (e.g. deployed via
Patch My PC) installs and runs without "WSL 2 is not installed" failures.

Contains no organization-specific values — safe to copy between tenants.

## What it does

1. Enables the `VirtualMachinePlatform` and `Microsoft-Windows-Subsystem-Linux`
   optional features.
2. Installs the modern WSL MSI from the official `microsoft/WSL` GitHub
   releases (includes the WSL 2 kernel, WSLg, and `wsl.exe`). If a `wsl*.msi`
   is placed in this folder before packaging, that local copy is used instead
   (fully offline — nothing downloaded at install time).
3. Sets the machine-wide default WSL version to 2.
4. Returns `3010` so Intune schedules a soft reboot; detection only passes
   after the reboot completes, keeping the Docker dependency chain honest.

No Linux distribution is installed — Docker Desktop provisions its own
(`docker-desktop`) WSL distro.

## Packaging

Using the [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool):

```
IntuneWinAppUtil.exe -c <this folder> -s Install-WSL2.ps1 -o <output folder>
```

Optional (recommended for locked-down networks): download the latest
`wsl.<version>.x64.msi` from https://github.com/microsoft/WSL/releases and
drop it in this folder **before** packaging so the install is fully offline.

## Intune Win32 app settings

| Setting | Value |
|---|---|
| Install command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-WSL2.ps1` |
| Uninstall command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-WSL2.ps1` |
| Install behavior | **System** |
| Device restart behavior | **Determine behavior based on return codes** |
| Return codes | `0` = Success, `3010` = Soft reboot, `1` = Failure (defaults are fine) |
| Operating system architecture | x64 |
| Minimum operating system | Windows 11 22H2 (or your baseline) |

### Detection rule

- Rule type: **Use a custom detection script**
- Script file: `Detect-WSL2.ps1`
- Run script as 32-bit process: **No**
- Enforce script signature check: **No** (or sign it per your policy)

The detection script requires both features to be fully `Enabled` (not
`EnablePending`) **and** the WSL package to be present, so the app stays
"pending reboot" until the machine actually restarts.

### Wiring it to Docker Desktop (Patch My PC)

In Intune, open the Patch My PC–created **Docker Desktop** app →
**Dependencies** → add this WSL 2 app with **Automatically install** = Yes.
Intune then guarantees WSL 2 (including its reboot) before Docker installs.

## Alternative: publish it through Patch My PC Cloud

Instead of hand-packaging and uploading to Intune, the same scripts can be
published as a PMPC Cloud **Custom App** so the whole chain is managed in one
console. See **[PMPC-Cloud-Setup.md](PMPC-Cloud-Setup.md)** for the field-by-field
wizard walkthrough, dependency wiring, validation steps, and troubleshooting.

## Windows 365 note

Nested virtualization is supported and enabled by default on 4 vCPU and larger
Cloud PC SKUs, so no extra configuration is needed there. The install script
logs `HypervisorPresent` for troubleshooting but does not change anything.

## Logs

- `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-WSL2.log`
- `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Uninstall-WSL2.log`

These sit alongside the Intune Management Extension logs, so they're picked up
by the Intune "Collect diagnostics" action.
