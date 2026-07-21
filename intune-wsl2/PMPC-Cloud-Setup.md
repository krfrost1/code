# Deploying the WSL 2 Package via Patch My PC Cloud

Step-by-step guide for publishing the scripts in this folder as a **Patch My PC
Cloud Custom App**, then wiring it as a **dependency** of a Docker Desktop
deployment so WSL 2 is always enabled before Docker installs.

This is the fully PMPC-managed alternative to hand-packaging an `.intunewin`
and uploading it to Intune (see [README.md](README.md) for that route).

## Why a dependency and not a requirement rule

An Intune *requirement rule* only gates installation — if WSL 2 were missing,
Docker would report "not applicable" and never install. A *dependency* actively
installs the parent app first, which is the desired behaviour. PMPC Cloud also
carries dependencies forward automatically each time it publishes a new version
of the child app, so the wiring survives Docker updates with no rework.

## Prerequisites

- A PMPC Cloud subscription that includes **Custom Apps** (Enterprise Plus tier
  or higher; the base patching tier does not include it). Verify under
  **Settings → Subscription → License**.
- The three scripts from this folder, downloaded to the machine you are
  browsing the PMPC Cloud portal from:
  - `Install-WSL2.ps1`
  - `Uninstall-WSL2.ps1`
  - `Detect-WSL2.ps1`
- Target devices must be able to reach `github.com` / `api.github.com` in
  SYSTEM context, because the install script downloads the WSL MSI at run time.
  If that egress is blocked, bundle the MSI instead — see
  [Offline installs](#offline-installs) below.

## Wizard walkthrough

The Custom Apps wizard runs:
**File → General Information → Configuration → Detection Rules → Summary**

> **Set Install Method first.** Changing it later resets every setting in the
> wizard.

### 1. File tab

| Field | Value |
|---|---|
| Install Method | **Installation Script** |
| Script | **Import Script** → `Install-WSL2.ps1` |
| Add Extra Folders and Files | *(skip — unless doing an offline install)* |

Script Name and Script Format populate automatically. Scripts run in the same
context as the app, which is set to System on the next tab. Limits are 1 MB per
script, 4 MB total, and 50,000 characters — this package is far below all three.

### 2. General Information tab

| Field | Value |
|---|---|
| Name | e.g. `WSL 2 Enablement` — this is what appears in the dependency picker |
| Vendor | Your organization, or `Microsoft` |
| Version | `1.0.0` |

Bump the version through **Update a Custom App** whenever the scripts change.

### 3. Configuration tab

| Field | Value | Notes |
|---|---|---|
| Install Context | **System** | DISM and the MSI install require SYSTEM |
| Architecture | **64-bit** | Also selects the registry view used for detection |
| Version | `1.0.0` | Match the General Information tab |
| Installed Apps Name | *blank* | Only used by default registry detection, which is overridden below |
| Silent Install Parameters | *blank* | The script takes no parameters |
| Conflicting Processes | *blank* | Nothing to terminate; do not list Docker here |
| MSI Product Code | *blank* | Not an MSI-type app |
| Uninstall Command | **Use Custom** → import `Uninstall-WSL2.ps1` | This option only appears for Installation Script apps |
| Minimum operating system | The Windows 11 baseline for the environment | |
| Min RAM / CPU speed / logical processors | *defaults* | Over-restricting silently makes the app "not applicable" |
| OS Architecture Requirements | 64-bit only | Usually auto-selected from Architecture |

Under **Return Codes**, confirm `0` = **Success** and `3010` = **Soft reboot**.
That mapping is load-bearing: it is what makes Intune report "pending reboot"
and re-evaluate detection *after* the restart rather than failing the install.
Add `3010` manually if it is missing.

The **Requirements** section (and **Additional Requirements Rules** — up to 10
File, Registry, or Script rules) is where requirement logic lives if you need it
for other apps. This package does not need any.

### 4. Detection Rules tab

| Field | Value |
|---|---|
| Method | Custom → **Use Custom Script** |
| Script | **Import Script** → `Detect-WSL2.ps1` |
| Associated with a 32-bit app on 64-bit clients | **Off** |

The 32-bit slider must stay off because the detection script calls
`Get-WindowsOptionalFeature`, which needs 64-bit context. The preview pane is
read-only by design.

Two platform constraints this package already satisfies: you cannot mix default
and custom detection for the same app, and PMPC does not sign customer-supplied
scripts (Intune does not require signing unless you enable signature checks).

### 5. Summary

Review and **Create**.

## Deploying and wiring the dependency

Creating a Custom App does not deploy it.

1. **Create a deployment** for the WSL 2 custom app and assign it to a **test
   group** only.
2. **Wait for it to publish successfully.** A dependency parent must already
   exist and have deployed successfully — apps in Failed, Retrying, or
   Processing states cannot be selected, and neither can apps whose only
   assignments are Uninstall or Update Only.
3. Open the **Docker Desktop deployment → Configurations tab → Dependencies**
   tool, and add the WSL 2 custom app with **auto-install** enabled.

From then on, PMPC copies the dependency forward to each new Docker version.

## Validation

Test on a genuinely clean device. On Windows 365, **reprovisioning a Cloud PC**
is the fastest way to get one and is a far more honest test than an
uninstall/reinstall on a machine that has already had WSL enabled (feature
state history, existing distro VHDs, and the `Lxss` registry tree all linger).

Confirm the full chain:

1. WSL 2 custom app installs and returns `3010`.
2. Device reboots; detection flips to installed.
3. Docker Desktop installs.
4. Docker starts and `wsl -l -v` lists the `docker-desktop` distro.

If you need to test the uninstall path on an existing device, remove Docker
Desktop first — disabling the WSL features underneath a working Docker install
leaves it broken and muddies the results. Then run the uninstall, **reboot**,
and verify with:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
```

Both should report `Disabled` before you re-test the install.

## Migrating from a manually created Intune app

If a hand-packaged version of this app is already deployed:

- Devices that already have WSL 2 will report **installed** to the new PMPC
  deployment and skip installation entirely, because both apps use the same
  detection script. No reinstall, no conflict.
- That also means an already-enabled device cannot validate the PMPC packaging
  path — use a clean or reprovisioned device for that.
- Once the PMPC deployment is confirmed working, remove the manual app's
  assignments and delete it. Leaving two apps with identical detection causes
  confusion later about which one owns WSL 2.

## Troubleshooting

**`0x87D1041C` — "application was not detected after installation completed
successfully."** The `3010` return-code mapping did not survive into the
published Intune app. Check the app's Return Codes in the Intune admin center;
if `3010` is not classified as a soft reboot, fix the mapping in PMPC and
republish. This is expected-to-fail-loudly behavior: the detection script
intentionally reports "not installed" while features sit in `EnablePending`, so
the app must not be marked complete until the reboot happens.

**Install log:**
`C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-WSL2.log`
(alongside the IME logs, so Intune's *Collect diagnostics* picks it up).
The uninstall script writes `Uninstall-WSL2.log` in the same folder.

**Detection returns false on a device that clearly has WSL.** Confirm the
detection script is not running in 32-bit mode — the "Associated with a 32-bit
app on 64-bit clients" slider must be off.

## Offline installs

Where target devices cannot reach GitHub, download
`wsl.<version>.x64.msi` from the official `microsoft/WSL` releases and add it
via **Add Extra Folders and Files** on the File tab. The install script prefers
a local `wsl*.msi` sitting next to it and skips the download entirely. Bumping
the WSL version then means updating the custom app rather than letting devices
pull the latest release themselves.

## Notes

- No Linux distribution is installed by design. Docker Desktop provisions its
  own `docker-desktop` WSL distro.
- Nested virtualization is supported and enabled by default on 4 vCPU and
  larger Cloud PC SKUs, so no additional configuration is required there. The
  install script logs `HypervisorPresent` purely as a troubleshooting
  breadcrumb.
