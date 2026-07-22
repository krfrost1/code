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
| Optional-feature enablement | Not covered — only needed if the image lacks them | Handled by the install script |
| Reboot handling | Not applicable when features are pre-enabled; otherwise pre-install script returns `3010` | App itself returns `3010`; Intune holds the chain |
| Scripts used | None, or `Enable-WSL2-Features.ps1` | `Install-WSL2.ps1`, `Uninstall-WSL2.ps1`, `Detect-WSL2.ps1` |

If neither route is available, see the
[hybrid fallback](#fallback-hybrid-manual-intune-app--pmpc-dependency).

## Why a dependency and not a requirement rule

An Intune *requirement rule* only gates installation — if WSL 2 were missing,
Docker would report "not applicable" and never install. A *dependency* actively
installs the parent app first, which is the desired behaviour. PMPC Cloud also
carries dependencies forward automatically each time it publishes a new version
of the child app, so the wiring survives Docker updates with no rework.

---

# Route A — PMPC catalog app

## What the catalog app does and does not cover

PMPC's catalog includes **`Windows Subsystem for Linux (MSI-x64)`** (added
August 2024). It packages Microsoft's WSL MSI — the WSL 2 kernel, WSLg, and
`wsl.exe` — and keeps it updated automatically.

It does **not** enable the Windows optional features WSL 2 depends on
(`VirtualMachinePlatform`, and `Microsoft-Windows-Subsystem-Linux` for inbox
compatibility), because an MSI cannot enable a Windows feature. It also does not
set the default WSL version to 2.

**Whether that matters depends on your image.** Windows 365 gallery images have
been observed to ship with both features **already enabled**, in which case the
catalog app alone is sufficient and no pre-install script is needed. Confirm
before deciding — see [Step 1](#steps).

```
Docker Desktop (PMPC catalog)
  └── depends on → Windows Subsystem for Linux (MSI-x64)   ← PMPC catalog, auto-updated
                     └── pre-install script (only if the features are not already enabled)
```

## Steps

1. **Check whether the features are already enabled on your image.** On a clean,
   freshly provisioned device that has had no WSL tooling deployed to it:

   ```powershell
   Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
   ```

   Both `Enabled` → skip steps 3 and 4 entirely; the catalog app is all you need.
   Either one `Disabled` → keep the pre-install script.

   Do not test this on a device that has already had `Install-WSL2.ps1` or an
   equivalent run against it — that script enables the features itself, so the
   result tells you nothing about the image. If such a device is all you have,
   read the *pre-existing* state out of its log instead:

   ```powershell
   Select-String -Path 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-WSL2.log' `
                 -Pattern 'current state|Enabling feature'
   ```

2. **Deploy the catalog app.** In PMPC Cloud, create a deployment for
   **Windows Subsystem for Linux (MSI-x64)** and assign it to a test group.
3. *(Only if step 1 showed a disabled feature.)* **Check for an existing PMPC
   script.** Some catalog apps ship with vendor-authored scripts that run
   automatically. In the **Scripts** tool, use the
   **`Customer Scripts | PMPC Scripts`** toggle to view them. You can read and
   disable a PMPC script but **cannot edit** it (name, format, contents, and
   arguments are locked). If PMPC's script already enables the features, you are
   done here.
4. *(Only if step 1 showed a disabled feature.)* **Attach the pre-install
   script.** Still in the **Scripts** tool, on the **Customer Scripts** side, add
   a **Pre-Install Script** and import `Enable-WSL2-Features.ps1`. Customer and
   PMPC scripts live in separate buckets, so adding yours does not replace or
   conflict with theirs. Pre-install scripts are generally available — no preview
   feature required. PMPC does not sign customer-supplied scripts; sign it
   yourself if your environment enforces signature checks.

   Optionally enable **"Don't attempt software update if the pre-script returns
   an exit code other than 0 or 3010"**. Both of this script's success codes are
   in that set, so the install still proceeds normally — but a genuine failure
   (exit `1`) will then stop the WSL install rather than letting it continue over
   a broken prerequisite. Without the checkbox, installation proceeds regardless
   of the script's exit code.

   Then set the deployment's **restart behaviour** so the device restarts after
   the features are enabled — see [The reboot problem](#the-reboot-problem).

5. **Let it deploy successfully.** A dependency parent must already exist and
   have deployed successfully; apps in Failed, Retrying, or Processing states
   cannot be selected, and neither can apps whose only assignments are Uninstall
   or Update Only.
6. **Wire the dependency.** Open the **Docker Desktop deployment →
   Configurations tab → Dependencies** tool and add the WSL catalog app with
   **auto-install** enabled.

From then on, PMPC copies the dependency forward to each new Docker version,
and updates the WSL package on its own schedule.

## The reboot problem

**This section only applies when the optional features are not already enabled
on your image.** Where they are pre-enabled — as on the Windows 365 gallery
images checked so far — nothing needs enabling, no restart is pending, and the
sequencing concern below disappears.

Otherwise: enabling `VirtualMachinePlatform` requires a restart before WSL 2
works, so the ordering of that restart relative to the Docker install matters.

`Enable-WSL2-Features.ps1` exits `3010` when it has left a reboot pending, and
`0` when the prerequisites were already active. PMPC treats both as success for
a pre-install script, so this is safe and does not abort the install behind it.

What it does *not* do by itself is guarantee that the device restarts before a
dependent app installs — the app's overall result still comes from the catalog
MSI, not from the pre-install script. Verify this behaves as expected in your
environment rather than assuming it.

## Keeping the script anyway

Even where the features are pre-enabled, `Enable-WSL2-Features.ps1` is
idempotent: it reads each feature's state, does nothing when they are already
enabled, and exits `0` in a second or two. Attaching it costs almost nothing and
insures against image drift — a new gallery image version, a switch to a custom
image, or non-Windows-365 devices joining the same deployment later. Dropping it
is reasonable for a homogeneous fleet on a known image; just re-check step 1 if
the image ever changes.

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
[Route A step 6](#steps).

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

# Assignment

Applies to all routes above. Assign in the deployment's **Assignments** tab.

## Only the child app needs assigning

Assign **Docker Desktop**. The WSL app installs automatically as a dependency
when Docker installs, so it does not need its own broad assignment — it only
needs to exist as a successfully deployed deployment, and its assignment type
must not be **Uninstall** or **Update Only**, either of which disqualifies it as
a dependency parent.

## User group or device group

Both work. For most app types an **Available** assignment is only valid against
user groups, but Win32 apps are the documented exception: per Microsoft, "Win32
apps can be assigned to either user or device groups."

Choose based on what the entitlement actually tracks:

| Use a **user group** when | Use a **device group** when |
|---|---|
| Entitlement is per-person ("who may have Docker") | Entitlement is per-machine ("these dev machines get Docker") |
| Seats are licensed per user — Docker Desktop requires a paid subscription for business use, so the group can mirror what you pay for | A defined set of machines is easier to enumerate than a set of people |
| You want self-service via Company Portal for a known audience | You want the assignment to be self-limiting to correct hardware |

**Recommended default:** a **user** security group with the **Available for
enrolled devices** intent, so entitled users install on demand from Company
Portal — plus a filter (below) to keep it off ineligible hardware.

Use **Required** instead if every targeted device should get Docker
unattended, with no user action.

## Guard against ineligible hardware with a filter

A user-group assignment follows the person to *every* device they own, including
ones where this cannot work:

- **Nested virtualization requires a 4 vCPU or larger Cloud PC.** Downsizing to
  2 vCPU disables it, and GPU Cloud PCs do not support it at all.
- **The WSL package is x64-only** (see [Notes](#notes)).

Apply an **Intune filter** to the assignment to scope it to eligible devices —
filters are available on Enterprise Plus and higher and are surfaced in PMPC's
Assignments tab. Filter on device model to include only Cloud PCs at 4 vCPU or
above; check the exact model string in the Intune admin center first, since Cloud
PC models surface with their specification in the name and the format matters for
the match.

A device-group assignment scoped to eligible machines achieves the same guard
without a filter.

> Assignment **intent is evaluated before the filter**. Avoid targeting the same
> app with conflicting intents across overlapping groups, or the filter may not
> behave as expected.

## Roll out in stages

Assign to a test group first and validate the full chain (below) before widening.
On Enterprise Plus and higher, **update rings** let you phase subsequent Docker
updates through a canary group rather than releasing to everyone at once.

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
- **x64 only.** Microsoft publishes both `wsl.<version>.x64.msi` and
  `wsl.<version>.arm64.msi`, but PMPC's catalog entry is explicitly
  `Windows Subsystem for Linux (MSI-x64)`, and `Install-WSL2.ps1` selects the
  x64 asset. Windows 365 Cloud PCs are x64, so this is moot for that scenario,
  and setting the app's architecture to 64-bit means ARM64 devices correctly
  evaluate as "not applicable" rather than failing. Supporting ARM64 would mean
  widening the script's asset filter and sourcing the package outside the PMPC
  catalog.
