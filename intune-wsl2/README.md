# WSL 2 Enablement for Docker Desktop

Scripts and deployment guidance for making WSL 2 a managed prerequisite of
Docker Desktop on Windows 11 — built for Windows 365 Cloud PCs, but nothing here
is specific to them.

Generic and tenant-agnostic: no organization-specific values, safe to copy
between environments.

## The problem

Docker Desktop requires WSL 2. WSL 2 in turn requires the
`VirtualMachinePlatform` Windows optional feature, which needs a **reboot**
before it takes effect. An MSI cannot enable a Windows feature, so simply
installing the WSL package is not enough — and the reboot means ordering
matters.

## What's in this folder

| File | Purpose |
|---|---|
| `Enable-WSL2-Features.ps1` | Enables the optional features and sets default WSL version 2. Pre-install script for the PMPC catalog WSL app. |
| `Install-WSL2.ps1` | Standalone: enables the features *and* installs the WSL MSI. Returns `3010` when a reboot is pending. |
| `Uninstall-WSL2.ps1` | Removes the WSL MSI and disables the features. |
| `Detect-WSL2.ps1` | Detection / verification. Exits `0` only when both features are fully `Enabled` and the WSL package is present. |
| `PMPC-Cloud-Setup.md` | **Start here** — Patch My PC Cloud deployment routes, dependency wiring, validation, troubleshooting. |

No Linux distribution is installed by design — Docker Desktop provisions its own
`docker-desktop` distro.

## Choosing a deployment route

**If you deploy Docker Desktop with Patch My PC**, read
**[PMPC-Cloud-Setup.md](PMPC-Cloud-Setup.md)**. The recommended route uses PMPC's
own catalog app `Windows Subsystem for Linux (MSI-x64)`, wired as a dependency of
the Docker deployment. It needs no preview features and lets PMPC keep the WSL
package updated.

Check your image first: where the optional features are already enabled — as on
the Windows 365 gallery images checked so far — the catalog app alone is enough
and no script is needed. Where they are not, attach `Enable-WSL2-Features.ps1` as
a pre-install script.

**Otherwise**, package this folder as a standalone Intune Win32 app using
`Install-WSL2.ps1`, as described below.

## Standalone Intune Win32 app

Uses `Install-WSL2.ps1`, which enables the features, installs the WSL MSI from
the official `microsoft/WSL` GitHub releases, sets the default version to 2, and
returns `3010` so Intune schedules a soft reboot. Detection only passes after
the reboot completes, which keeps a Docker dependency chain honest.

### Packaging

Using the [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool):

```
IntuneWinAppUtil.exe -c <this folder> -s Install-WSL2.ps1 -o <output folder>
```

Optional, and recommended for locked-down networks: download the latest
`wsl.<version>.x64.msi` from https://github.com/microsoft/WSL/releases and drop
it in this folder **before** packaging. The install script prefers a local
`wsl*.msi` and skips the download, making the install fully offline.

### App settings

| Setting | Value |
|---|---|
| Install command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-WSL2.ps1` |
| Uninstall command | `%windir%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-WSL2.ps1` |
| Install behavior | **System** |
| Device restart behavior | **Determine behavior based on return codes** |
| Return codes | `0` = Success, `3010` = Soft reboot, `1` = Failure (defaults are fine) |
| Operating system architecture | x64 |
| Minimum operating system | Windows 11 22H2, or your baseline |

### Detection rule

- Rule type: **Use a custom detection script**
- Script file: `Detect-WSL2.ps1`
- Run script as 32-bit process: **No**
- Enforce script signature check: **No**, or sign it per your policy

The detection script requires both features to be fully `Enabled` (not
`EnablePending`) **and** the WSL package to be present, so the app stays
"pending reboot" until the machine actually restarts.

### Wiring it to Docker Desktop

In Intune, open the Docker Desktop app → **Dependencies** → add this WSL 2 app
with **Automatically install** = Yes. Intune then guarantees WSL 2, including
its reboot, before Docker installs.

## Windows 365 note

Nested virtualization is supported and enabled by default on 4 vCPU and larger
Cloud PC SKUs, so no extra configuration is needed there. The scripts log
`HypervisorPresent` for troubleshooting but do not change anything.

## Logs

All written alongside the Intune Management Extension logs in
`C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`, so Intune's
*Collect diagnostics* action picks them up:

- `Enable-WSL2-Features.log`
- `Install-WSL2.log`
- `Uninstall-WSL2.log`
