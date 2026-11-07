# LidGlow

A native macOS menu-bar app for the dedicated logo-backlight interface found on this Mac. Original experimental software, not a copy of another app. It cannot add a light to a Mac that has no compatible hardware.

## TL;DR / 快速开始

**Apple Silicon + macOS 13 or newer + a compatible logo-backlight device. This is experimental, not a universal Mac lighting app.** Installation works without Xcode/Homebrew; hardware support is detected by the app and unsupported machines stay read-only.

One command in Terminal installs the prebuilt **v0.2.1** app in `/Applications` and opens it:

```sh
/bin/bash -c "$(curl --fail --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/chuxuanfu/LidGlow/main/install.sh)"
```

Read [install.sh](install.sh) before executing downloaded code. The installer verifies a SHA-256 checksum and the bundle's code signature, skips an identical installed build, preserves the previous app on upgrades, refuses to replace a running copy, and never uses sudo or disables security. A changed ad-hoc signature may need fresh native permission even if Settings still shows an enabled switch. Checksums detect corruption, not a compromised publisher; this build is **ad-hoc signed and not Apple-notarized**. A managed Mac may block it.

Prefer a disk image? Download [LidGlow 0.2.1 DMG](https://github.com/chuxuanfu/LidGlow/raw/refs/heads/main/dist/LidGlow-0.2.1-macos-arm64.dmg), open it, and drag **LidGlow.app → Applications**. Alternatively, the DMG's **Install LidGlow.command** installs the bundled app and opens it. Quit an existing copy with **Restore & Quit** first. [ZIP app download](https://github.com/chuxuanfu/LidGlow/raw/refs/heads/main/dist/LidGlow-0.2.1-macos-arm64.zip) · [Checksums](dist/SHA256SUMS)

1. Open **Applications → LidGlow**. It lives in the menu bar and starts in **Breathe**.
2. For **Music** or **Auto**, select that mode and accept the app's disclosure. Grant **Screen & System Audio Recording** in macOS when asked, then reopen if macOS requires it.
3. **Launch at login** is optional. **Restore & Quit** restores the original settings before exiting.

中文：一条命令下载并校验 App，安装到 Applications 后打开。首次音乐/自动模式需要你亲自同意 macOS 的屏幕与系统音频录制许可，脚本不能代替授权。无需麦克风、辅助功能、完全磁盘访问或 root 权限。本版未做 Apple Developer ID 签名/公证；若 macOS 阻止打开，请先核实来源，再按系统“隐私与安全性”的正规提示处理，不要关闭系统安全保护。

See [Quick Start](QUICKSTART.md) for user-only installation, upgrades, uninstall and permission troubleshooting. See [Distribution](DISTRIBUTION.md) for repeatable DMG builds and the Developer ID/notarization path.

## Controls

- **Breathe** is selected on every launch. The previous lighting mode is never restored automatically. Maximum brightness, breathing period and beat sensitivity are remembered.
- **Manual**, **Off**, and **Restore / System control** are also available.
- **Music** uses system output audio to create high-contrast beat pulses. Silence fades to zero.
- **Auto · Breathe + Music** breathes in silence and follows audio when sound returns. Activity hysteresis and a short crossfade avoid rapid mode switching.
- **Launch at login** is optional and off until the user enables it. It uses Apple's ServiceManagement API and reports approval/error states rather than silently claiming success. Keep the app at its current location after enabling it. Login means after the user signs in, not before login.
- **Restore & Quit** restores the complete original mapping and mode before quitting. The preview shows the requested numeric brightness, not measured physical light.

All app-authored controls, dialogs and error messages are in English. System-owned permission dialogs follow the Mac's language settings.

## Build and run

On an Apple Silicon Mac with macOS 13+ and Apple's Xcode Command Line Tools:

```sh
./test.sh
./build.sh
open "build/LidGlow.app"
```

The build uses only installed Apple tools. It does not download dependencies, install the app, run it, or enable login launch. Run `./install.sh --app "$PWD/build/LidGlow.app"` to install locally, or `./package.sh` to create the distributable DMG, app ZIP and checksums in `dist/`. The app has a local ad-hoc signature, not a Developer ID signature or notarization. Rebuilding changes its signature and may invalidate an earlier capture permission. Follow macOS's supported permission flow for this app only; never disable system protection or reset unrelated permissions.

For an ordinary window while testing, use `open "build/LidGlow.app" --args --debug-window`. Normal use is a menu-bar app. The new original app icon is in `Assets/`; regenerate it with `swift tools/generate-icon.swift`.

## Audio and privacy

Music and Auto use ScreenCaptureKit to receive system output audio. They do not use the microphone, register screen-video output, save audio, or send anything over a network. The macOS permission can be named **Screen & System Audio Recording**, depending on OS version. LidGlow explains this once before starting capture. After Continue, that app-owned disclosure consent is remembered across launches; macOS capture authorization is still enforced by the system. Auto keeps audio capture active while breathing so it can detect sound returning. Selecting another mode, capture errors, sleep/lock or quitting stops capture.

Short analysis windows preserve transients. The detector uses adaptive energy/bass-onset normalization, rather than multiplying RMS until it saturates. Beat sensitivity changes detection/contrast while keeping headroom. Protected media, unusual output devices, routing and revoked permissions can prevent audio from being received. These cases and physical light appearance must be checked on the actual device.

## Hardware safety and limitations

- Requires `IODeviceTree:/arm-io/pwm1/bklb-backlight` and readable, validated original mapping/mode. Unsupported hardware remains read-only.
- Uses the private CoreBrightness `BrightnessSystemClient` interface. Methods and signatures are checked, but future OS versions can still change behavior.
- Writes `LEPWMBrightnessNitsMapping`, `LEBacklightMode` and `DisplayPowerStateEvent`. The last event is private; its effects on display-power behavior cannot be guaranteed. No display-brightness API is called.
- Maximum brightness is capped at the original mapping's maximum. Ambient-light limits and system fades are not bypassed. Requested percentages are not measured physical brightness. System constraints may still limit visual contrast and pulse speed.
- Never requires root, sudo, disabled SIP or weakened security settings. Do not run another logo-backlight controller at the same time.
- Sleep, screen-off and lock pause effects/capture while preserving the selected mode, maximum brightness, breathing period and sensitivity. After the system and display wake and the session unlocks, the original hardware state is restored first, then the previous mode resumes. Music/Auto restarts capture only under the existing native permission. A restore/capture failure stops effects and shows an error. A fresh app launch still starts in Breathe.
- There is no real-time crash watchdog. Force quitting may leave the light at its last level until recovery or system takeover. A snapshot is not a guarantee of immediate crash recovery.

## Recovery

Before the first write in an ownership session, the complete original mapping and mode are saved atomically to:

`~/Library/Application Support/LidGlowLab/recovery.plist`

The existing internal storage directory and bundle identifier `local.lidglow.lab` are intentionally retained for upgrade continuity. The snapshot includes model, OS build and a hashed device identifier only to reject another device's or system version's recovery data. It is local and must not be shared or copied from another Mac.

A pending recovery prevents automatic breathing until the user restores it. Corrupt or incompatible data is never overwritten or forcibly applied. Recovery data is removed only after all original settings are restored. If restoration fails, Retry, Cancel Quit, and Quit & Keep Recovery are offered. Installation scripts preserve an existing app as a dated hidden backup beside the installed app. Recovery data and personal preferences are never bundled or uploaded. Local source backups are excluded from Git.

## Verification

See `TEST-RESULTS.md` for the exact checks completed on this build. Numeric tests and successful hardware readback do not prove the visible appearance of the physical logo. Sleep/wake, lock, multiple displays, DRM, audio device changes and permission revocation require broader manual validation.

## Source

- `main.m`: native English UI, mode state, login launch and recovery lifecycle.
- `Lifecycle.c` / `test_lifecycle.c`: sleep/display/lock coordination and resume-mode regression tests.
- `Hardware.m`: conservative capability checks, capped writes and complete restoration.
- `AudioMeter.m`: local ScreenCaptureKit audio analysis.
- `Signal.c` / `test_signal.c`: portable DSP and repeatable regression tests.
- `Assets/` / `tools/generate-icon.swift`: original icon and reproducible source.
