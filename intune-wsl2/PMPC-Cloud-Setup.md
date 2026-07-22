# Enabling WSL 2 for Docker Desktop via Patch My PC Cloud

Docker Desktop fails to install or run when WSL 2 is missing. This guide covers
making WSL 2 a managed prerequisite of a Docker Desktop deployment in PMPC
Cloud, so the dependency is satisfied automatically on every device.

Two routes are documented. **Route A is recommended** — it uses only generally
available features and lets PMPC keep the WSL package itself up to date.

| | Route A — catalog app | Route B — Custom App |
|---|---|---|
| WSL package source | PMPC catalog, auto-updated | Downloaded by our script at install time |
| Preview features needed | None | **Custom Scripted Apps App Catalog** (company-level toggle) |
| Reboot handling | Configured on the deployment (verify) | Script returns `3010`; Intune holds the chain |
| Scripts used | `Enable-WSL2-Features.ps1` | `Install-WSL2.ps1`, `Uninstall-WSL2.ps1`, `Detect-WSL2.ps1` |

If neither route is available, see the
[hybrid fallback](#fallback-hybrid-manual-intune-app--pmpc-dependency).

## Why a dependency and not a requirement rule

An Intune *requirement rule* only gates installation — if WSL 2 were missing,
Docker would report "not applicable" and never install. A *dependency* actively
installs the parent app first, which is the desired behaviour. PMPC Cloud also
carries dependencies forward automatically each time it publishes a new version
of the child app, so the wiring survives Docker updates with no rework.

---

# Route A — PMPC catalog app + pre-install script

## What the catalog app does and does not cover

PMPC's catalog includes **`Windows Subsystem for Linux (MSI-x64)`** (added
August 2024). It packages Microsoft's WSL MSI — the WSL 2 kernel, WSLg, and
`wsl.exe` — and keeps it updated automatically.

It does **not**:

- enable the `VirtualMachinePlatform` Windows optional feature, which WSL 2
  requires and which cannot be enabled by an MSI; or
- set the default WSL version to 2 (per PMPC's own guidance, this must be
  handled separately).

`Enable-WSL2-Features.ps1` in this folder closes exactly that gap and nothing
more. Attaching it as a **pre-install script** produces:

```
Docker Desktop (PMPC catalog)
  └── depends on → Windows Subsystem for Linux (MSI-x64)   ← PMPC catalog, auto-updated
                     └── pre-install script → optional features + default version 2
```

## Steps

1. **Deploy the catalog app.** In PMPC Cloud, create a deployment for
   **Windows Subsystem for Linux (MSI-x64)** and assign it to a test group.
2. **Attach the pre-install script.** In that deployment's **Configurations**
   tab, add the **Scripts** tool, choose **Pre-Install Script**, and import
   `Enable-WSL2-Features.ps1`. Pre-install scripts are generally available — no
   preview feature required. Note that PMPC does not sign customer-supplied
   scripts; sign it yourself if your environment enforces signature checks.
3. **Set the restart behaviour** on the deployment so the device restarts after
   the features are enabled. See [The reboot problem](#the-reboot-problem) — do
   not skip this.
4. **Let it deploy successfully.** A dependency parent must already exist and
   have deployed successfully; apps in Failed, Retrying, or Processing states
   cannot be selected, and neither can apps whose only assignments are Uninstall
   or Update Only.
5. **Wire the dependency.** Open the **Docker Desktop deployment →
   Configurations tab → Dependencies** tool and add the WSL catalog app with
   **auto-install** enabled.

From then on, PMPC copies the dependency forward to each new Docker version,
and updates the WSL package on its own schedule.

## The reboot problem

This is the one place Route A is weaker than Route B, and it needs verifying in
your environment.

Enabling `VirtualMachinePlatform` requires a restart before WSL 2 actually
works. `Enable-WSL2-Features.ps1` deliberately exits `0` even when a reboot is
pending, because a non-zero exit from a pre-install script can abort the install
that follows it. The consequence is that nothing automatically signals "reboot
required" to Intune the way a `3010` return code does in Route B — so Docker
could begin installing while WSL 2 is still inactive.

Mitigations, in order of preference:

1. Configure the WSL deployment's **restart behaviour** to force a restart after
   install, and confirm in the Intune admin center that the published app
   reflects it.
2. Stage the rollout so the WSL deployment lands well ahead of the Docker
   deployment (for example on separate update rings), giving devices a normal
   reboot cycle in between.
3. If neither is reliable in practice, use **Route B**, whose `3010` return code
   makes Intune hold the dependency chain until the restart happens.

Verify on a clean device before rolling out broadly — see [Validation](#validation).

---

# Route B — Custom App built from the scripts in this folder

Use this when you want the `3010` reboot semantics, or when the catalog app is
unsuitable. It publishes `Install-WSL2.ps1` as a script-only Custom App.

> **Script-only Custom Apps require a preview feature.** By default the Custom
> Apps wizard only accepts an EXE or MSI as the primary installer file. Uploading
> a `.ps1` on its own depends on the **Custom Scripted Apps App Catalog** public
> preview feature, which is enabled at the *company* level in the PMPC Cloud
> portal's preview-features settings and therefore needs an administrator who
> owns the tenant. This is not a licensing tier issue — Custom Apps itself is
> included in Enterprise Plus.

## Prerequisites

- A PMPC Cloud subscription that includes **Custom Apps** (Enterprise Plus tier
  or higher; the base patching tier does not include it). Verify under
  **Settings → Subscription → License**.
- The **Custom Scripted Apps App Catalog** preview feature enabled (see above).
- `Install-WSL2.ps1`, `Uninstall-WSL2.ps1`, and `Detect-WSL2.ps1` downloaded to
  the machine you are browsing the PMPC Cloud portal from.
- Target devices able to reach `github.com` / `api.github.com` in SYSTEM
  context, because the install script downloads the WSL MSI at run time. If that
  egress is blocked, bundle the MSI instead — see
  [Offline installs](#offline-installs).

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

Review and **Create**, then create a deployment for the app, assign it to a test
group, and wire it as a dependency of Docker Desktop as described in
[Route A step 5](#steps).

---

# Fallback: hybrid (manual Intune app + PMPC dependency)

Use this when neither the catalog app nor the preview feature is workable. It
reaches the same end state, with the WSL 2 app listed in Intune rather than the
PMPC portal.

1. Package this folder as a Win32 app and upload it to Intune by hand, using the
   settings in [README.md](README.md).
2. In Intune, open the PMPC-published **Docker Desktop** app → **Dependencies**
   → add the WSL 2 app with **Automatically install** = Yes.
3. Leave the rest of the Docker lifecycle to PMPC.

PMPC moves dependencies and assignments from the current version to the new one
each time it publishes an update, so the dependency is expected to survive
Docker updates untouched. The documentation is explicit about carrying
dependencies forward but does not specifically call out parents that were
created manually in Intune rather than by PMPC — worth confirming across the
first update cycle after setting this up.

---

# Validation

Test on a genuinely clean device. On Windows 365, **reprovisioning a Cloud PC**
is the fastest way to get one and is a far more honest test than an
uninstall/reinstall on a machine that has already had WSL enabled (feature state
history, existing distro VHDs, and the `Lxss` registry tree all linger).

Confirm the full chain:

1. The WSL app installs — for Route A, check the pre-install script log for
   feature enablement; for Route B, confirm the app returns `3010`.
2. The device restarts, and after the restart both features report `Enabled`:
   ```powershell
   Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
   wsl --status
   ```
3. Docker Desktop installs.
4. Docker starts and `wsl -l -v` lists the `docker-desktop` distro.

`Detect-WSL2.ps1` doubles as a manual verification script: it exits `0` only
when both features are fully `Enabled` (not `EnablePending`) *and* the WSL
package is present.

For Route A specifically, confirm Docker does not begin installing before the
restart has happened. If it does, revisit [The reboot problem](#the-reboot-problem).

## Migrating from a manually created Intune app

If a hand-packaged version of this app is already deployed:

- Devices that already have WSL 2 will report **installed** to the new
  deployment and skip installation entirely, because the detection logic is the
  same. No reinstall, no conflict.
- That also means an already-enabled device cannot validate the new packaging
  path — use a clean or reprovisioned device for that.
- Once the new deployment is confirmed working, remove the manual app's
  assignments and delete it. Leaving two apps with identical detection causes
  confusion later about which one owns WSL 2.

# Troubleshooting

**`0x87D1041C` — "application was not detected after installation completed
successfully"** (Route B). The `3010` return-code mapping did not survive into
the published Intune app. Check the app's Return Codes in the Intune admin
center; if `3010` is not classified as a soft reboot, fix the mapping in PMPC
and republish. This is expected-to-fail-loudly behaviour: the detection script
intentionally reports "not installed" while features sit in `EnablePending`, so
the app must not be marked complete until the reboot happens.

**Docker installs but fails to start, complaining about WSL 2** (Route A). The
device almost certainly has not restarted since the features were enabled. Check
`Enable-WSL2-Features.log` for the `REBOOT PENDING` line, then see
[The reboot problem](#the-reboot-problem).

**Detection returns false on a device that clearly has WSL.** Confirm the script
is not running in 32-bit mode — the "Associated with a 32-bit app on 64-bit
clients" slider must be off.

**Logs**, all alongside the Intune Management Extension logs in
`C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` (so Intune's *Collect
diagnostics* picks them up):

- `Enable-WSL2-Features.log` (Route A pre-install script)
- `Install-WSL2.log` / `Uninstall-WSL2.log` (Route B)

# Offline installs

Route A needs no egress to GitHub — PMPC hosts the WSL package.

For Route B, where target devices cannot reach GitHub, download
`wsl.<version>.x64.msi` from the official `microsoft/WSL` releases and add it via
**Add Extra Folders and Files** on the File tab. The install script prefers a
local `wsl*.msi` sitting next to it and skips the download entirely. Bumping the
WSL version then means updating the custom app rather than letting devices pull
the latest release themselves.

# Notes

- No Linux distribution is installed by design. Docker Desktop provisions its
  own `docker-desktop` WSL distro.
- Nested virtualization is supported and enabled by default on 4 vCPU and larger
  Cloud PC SKUs, so no additional configuration is required there. The scripts
  log `HypervisorPresent` purely as a troubleshooting breadcrumb.
- Strictly, only `VirtualMachinePlatform` is required by the MSI-based WSL
  package; `Microsoft-Windows-Subsystem-Linux` is enabled as well for
  compatibility with older tooling and inbox WSL. Enabling both is harmless.
