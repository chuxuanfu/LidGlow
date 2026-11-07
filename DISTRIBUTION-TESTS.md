# Distribution and wake-resume verification: 0.2.1

## Passed locally

- Apple Silicon native build targeting macOS 13+, Info.plist validation, strict ad-hoc code-signature verification.
- Existing signal-engine regression suite, including 300,000 randomized invariant checks and all 20 audio-sensitivity settings.
- Mock-only recovery regression (no real hardware writes).
- New lifecycle regression: all six modes, screen/system/lock event orderings, duplicate notifications and repeated cycles.
- Tests of the actual application's suspend/resume methods using fake hardware/audio/UI collaborators: pending audio is cancelled, no resume while a known lock/sleep remains, the prior mode resumes once, failed restoration prevents restart, and explicit Off during suspension takes priority.
- Audio-failure-before-sleep ordering: capture stops immediately, a brief settling window lets the sleep notification preserve the requested mode, and the stale error is cancelled. An unrelated audio error still takes the error path.
- Installer regression: first install, identical-build reinstall as a no-op (also checked with the installed app running), changed-signature warning, upgrade with retained backup, rejection of damaged signatures and symlink input, preservation of the existing app and concurrent-install lock.
- DMG structure/checksum and ZIP app signature validation are part of packaging.

## Current installed audio authorization verified

After the user renewed only LidGlow's entry through native System Settings, the unchanged installed 0.2.1 app started Music without a permission/error dialog. A short low-volume synthetic system-output test produced 74 brightness samples, peaking at approximately 932.6 nits within the user's existing 100% ceiling. After the test audio ended, all 21 silence samples were exactly zero with mode 0. This verifies actual output-audio capture for this build on this Mac, not only the permission switch's appearance. These figures describe system parameters, not measured physical light.

No app rebuild, re-signing or permission reset was performed for this verification. Packaging now supports copying that exact verified app, and the source/staged bundles are compared byte-for-byte with signatures verified.

## Limits

Mock lifecycle tests do not put the physical Mac to sleep or lock it. Real sleep/wake/lock timing, physical logo appearance, DRM, multiple displays, audio routing and revoked permissions still require device-specific testing. A capture error arriving outside the short transition window is treated as a real failure and stops effects safely.

Version 0.2.1 pauses on screen-off, sleep and lock, and restores the selected mode/parameters after the matching wake and unlock events. A fresh process launch still starts in Breathe. Recovery failures stop automatic restart.

This release is ad-hoc signed, not Developer ID signed or notarized. A new binary can require LidGlow's audio-capture permission to be renewed through native System Settings. No permission resets, security bypasses or unrelated permissions are performed by the app or installer.

Historical device/audio tests for the preceding app are retained in TEST-RESULTS.md and are not claims of fresh 0.2.1 hardware validation.
