TITLE OPTIONS (pick one):

A) WSL2 + Docker Desktop on Windows 365 via Patch My PC — what I learned, including the day I wasted
B) PSA: Patch My PC has a WSL catalog app. I built a custom Win32 package before checking.
C) Deploying Docker Desktop to Cloud PCs: the WSL2 prerequisite chain, and 5 things that aren't documented anywhere

---

BODY:

Spent a while getting Docker Desktop to deploy cleanly to Windows 365 Cloud PCs via Patch My PC, and hit several things I couldn't find written down anywhere. Posting in case it saves someone the same detours — including the one that was entirely self-inflicted.

**TL;DR**

- Patch My PC already has a `Windows Subsystem for Linux (MSI-x64)` catalog app. Check the catalog before you build anything.
- Windows 365 gallery images appear to ship with `VirtualMachinePlatform` and `Microsoft-Windows-Subsystem-Linux` **already enabled** — so you may not need any DISM step at all.
- Script-only Custom Apps in PMPC Cloud require a **public preview feature**, not just an Enterprise Plus license.
- Use a **dependency**, not a requirement rule, for the Docker → WSL2 chain.
- End state: two catalog apps and one dependency. No custom packaging at all.

---

**The setup:** Docker Desktop needs WSL 2. WSL 2 needs the `VirtualMachinePlatform` optional feature, which needs a reboot. An MSI can't enable a Windows feature, so "just install the WSL package" isn't sufficient on its own — and the reboot means ordering matters.

**1. Check the vendor catalog first.** I wrote a full Win32 package — install/detect/uninstall scripts, DISM feature enablement, MSI download from the microsoft/WSL GitHub releases, `3010` return code, the works. It worked fine. Then I found PMPC has had a WSL catalog app since August 2024 that installs and auto-updates the same MSI. Genuinely useful lesson: when your deployment tool is a patching product, "is this already in the catalog?" is question one, not question ten.

**2. Windows 365 images already have the features enabled.** This was the real surprise. I assumed I needed DISM to turn on `VirtualMachinePlatform`. Checking the pre-existing state on a Cloud PC showed both features already `Enabled` out of the box. If that holds for your image, the catalog app alone is enough — no scripts, no feature enablement, no pending reboot to sequence around.

Verify on **your** image rather than trusting mine, and don't test it on a machine where you've already run something that enables the features — check a freshly provisioned device, or read the pre-existing state out of your install log.

**3. Script-only Custom Apps need a preview feature.** If you try to upload a bare `.ps1` as a PMPC Custom App and the wizard only offers you EXE/MSI, that's not a licensing problem. It's the **Custom Scripted Apps App Catalog** public preview feature, enabled at the company level. Custom Apps itself is included from Enterprise Plus, so it's easy to misdiagnose as a tier issue. If you don't own the tenant, you'll need whoever does to flip it.

**4. Dependency, not requirement rule.** A requirement rule only gates — if WSL2 is missing, Docker reports "not applicable" and silently never installs. A dependency actively installs the parent first. PMPC also carries dependencies forward when it publishes new app versions, so the wiring survives Docker updates.

**5. Assignment: scope with a filter, not with the dependency.** Nested virtualization on Windows 365 needs a **4 vCPU or larger** Cloud PC — downsizing to 2 vCPU disables it, and GPU Cloud PCs don't support it at all. A user-group assignment follows the person to every device they own, so put an Intune filter on the assignment to keep it off ineligible hardware. Win32 apps are the documented exception that can take an **Available** assignment against either user *or* device groups, so you have both options.

Also worth knowing: the dependency attaches to the *Windows* Docker deployment only. macOS Docker Desktop is a separate app and Win32 dependencies are Windows-only, so Mac fleets are unaffected. And if anyone needs **Windows containers**, they need Hyper-V rather than WSL2 — WSL installing alongside is harmless for them, just unused.

**Assorted things that cost me time:**

- The catalog app is **x64 only**. Microsoft publishes an ARM64 WSL MSI, but it isn't catalogued.
- PMPC **pre-install scripts treat both `0` and `3010` as success**, so returning `3010` from a pre-install script is safe and won't abort the install behind it.
- Some catalog apps ship with **vendor-authored scripts** already attached. There's a `Customer Scripts | PMPC Scripts` toggle — you can view and disable theirs but not edit it, and your own scripts live in a separate bucket, so you're not overwriting anything by adding one.
- If you see **`0x87D1041C`** ("app was not detected after installation completed successfully") on a custom package, your `3010` return-code mapping probably didn't make it into the published Intune app.
- **Cleanup trap:** if you're replacing a hand-built WSL app, do *not* give it an Uninstall assignment — that runs your uninstall logic and disables `VirtualMachinePlatform`, breaking Docker on machines that were working. Remove the assignments and delete the app instead. Deleting an Intune app doesn't uninstall it from devices, which is exactly what you want here.

**Where I landed:** deploy the PMPC catalog WSL app, add it as an auto-install dependency of the Docker Desktop deployment, done. No custom packaging, no preview features, no reboot choreography. Both apps advertised in Company Portal and installed cleanly on a Cloud PC. (I'm leaving WSL advertised on its own as well — it's useful standalone, and the dependency works the same either way.)

Which is roughly where I'd have started if I'd looked at the catalog on day one.

Scripts and a fuller deployment guide, if useful to anyone:
https://github.com/krfrost1/code/tree/master/intune-wsl2

Happy to be told I've got any of this wrong — particularly the Windows 365 image behaviour, since I've only checked it on one image version.
