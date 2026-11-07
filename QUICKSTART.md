# LidGlow Quick Start

## Requirements

- Apple Silicon Mac, macOS 13 or newer. Intel, Windows and Linux are unsupported.
- The exact compatible logo-backlight interface must be present. Many Macs have no illuminated logo at all. On unsupported hardware the app shows a read-only message and makes no hardware writes.
- No Homebrew, Xcode or developer tools are required for the prebuilt app. Source builds require Apple's Command Line Tools.
- This is experimental software using a private Apple interface. The included release is locally/ad-hoc signed, not Developer ID signed or Apple-notarized. Corporate security policy can prevent installation or launch.

## Install in one command

```sh
/bin/bash -c "$(curl --fail --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/chuxuanfu/LidGlow/main/install.sh)"
```

Review the script first if you prefer:

```sh
curl --fail --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/chuxuanfu/LidGlow/main/install.sh -o LidGlow-install.sh
less LidGlow-install.sh
/bin/bash LidGlow-install.sh
```

The script downloads the published prebuilt app, checks SHA-256 and bundle integrity, installs to `/Applications/LidGlow.app`, and opens it. If the identical build is already installed, it leaves the app untouched, even when running. A changed signature is called out before an upgrade. It requires no sudo, installs no dependencies, and never changes Gatekeeper, SIP, TCC or login items. The checksums and app are supplied by the same publisher; they are not independent proof of trust.

If you cannot write to `/Applications`, install for your account:

```sh
/bin/bash LidGlow-install.sh --user
```

Use `--no-open` to install without launching. The installer fails safely if LidGlow is running: select **Restore & Quit**, then try again. A failed download or validation does not replace the existing app. Previous apps are kept in a hidden `.LidGlow-backup-DATE-PID` directory beside the installed app, and the exact path is printed. Personal preferences and recovery data stay in your user Library.

## Install from the DMG

1. Download and open `LidGlow-0.2.1-macos-arm64.dmg`.
2. Select **Restore & Quit** in an older running LidGlow.
3. Drag **LidGlow.app** onto **Applications**, or double-click **Install LidGlow.command** for a checked install with backup.
4. Open LidGlow from Applications, then eject the DMG. Do not run it directly from the disk image or move it after enabling login launch.

macOS may block an unnotarized download. Inspect the source and provenance before proceeding. If you trust it, use Apple's supported **System Settings → Privacy & Security → Open Anyway** flow when available. If your administrator blocks it, ask them for an approved build. Do not remove quarantine or disable system protections.

## Permissions and first use

- Breathe, Manual and Off need no recording permission.
- Music and Auto analyze **system output audio** with ScreenCaptureKit. After the app explains this and you choose Continue, follow the native macOS permission dialog.
- The permission is called **Screen Recording** or **Screen & System Audio Recording**, depending on macOS. Open **System Settings → Privacy & Security**, enable this app if requested, and quit/reopen when macOS asks.
- LidGlow registers audio output only, not screen-frame output. It never uses the microphone, saves recordings or uploads audio. It does not need Accessibility, Full Disk Access, camera or administrator permissions.
- Permissions belong to each Mac and signed app. An installer cannot pre-grant them. Rebuilding/ad-hoc updates can invalidate earlier consent. Renew only LidGlow's permission through System Settings if necessary; never globally reset privacy permissions.
- Launch at login is optional and initially off. Enable it from the app after installing to a permanent location. macOS may ask you to approve it under Login Items.

The menu-bar panel appears on launch. Breathe is the initial mode, Music follows beats, and Auto breathes in silence and follows music when it returns. Screen-off, sleep and lock pause the effect; after wake and unlock, your selected mode and settings resume. A normal quit/relaunch still starts in Breathe. Restore returns control to the system. **Restore & Quit** restores before exiting; do not force-quit during normal use.

### If the permission switch is enabled but Music/Auto still fails

An enabled switch can refer to an older ad-hoc build. This is different from the app's own one-time explanation. Repeatedly toggling the switch or reinstalling the identical app may not fix a stale code-signature record.

1. Choose **Restore & Quit** and close other copies of LidGlow. Keep one installed copy in `/Applications` (or your chosen `~/Applications` location).
2. In **System Settings → Privacy & Security → Screen & System Audio Recording**, review the LidGlow entry. Use the system's supported removal/addition flow for **LidGlow only**, selecting the installed app at that exact path. Follow any restart prompt. Do not change other apps' permissions.
3. Open the installed app and select Music/Auto again. If an organization manages this setting, ask its administrator. Do not disable system protection, edit the TCC database, or run a global privacy reset.

The installer never performs these permission changes. First-time users must approve native capture access themselves. Future ad-hoc updates, OS policy changes or periodic macOS consent checks can ask again. **Zero permission prompts or permanent authorization cannot be guaranteed.** For a maintained public release, the distributor should use a stable Developer ID identity and notarization; even that does not bypass native consent.

## Build, package and install from source

```sh
git clone https://github.com/chuxuanfu/LidGlow.git
cd LidGlow
./test.sh
./build.sh
./install.sh --app "$PWD/build/LidGlow.app"
./package.sh
```

`package.sh` creates the DMG, a ZIP containing the `.app`, and SHA256SUMS in `dist/`. To distribute an already-tested build without changing its signature, use `./package.sh --app /Applications/LidGlow.app`. It does not upload, notarize, install or launch anything. Developer ID signing is optional; see DISTRIBUTION.md.

## Uninstall / rollback

Turn off Launch at login in the app if enabled, select **Restore & Quit**, then move LidGlow.app to Trash in Finder. Keep recovery data until restoration succeeds. To roll back, quit first and use Finder to restore the previous bundle from the backup path printed by the installer, renaming it `LidGlow.app`. No launch daemon, helper, background installer or global setting is installed.

## Known limits

Private CoreBrightness behavior can change with macOS. Numeric tests do not prove the physical appearance of a logo. Sleep/wake/lock, DRM, unusual audio routing, multiple displays and live permission revocation need device-specific validation. Do not run another backlight controller at the same time.
