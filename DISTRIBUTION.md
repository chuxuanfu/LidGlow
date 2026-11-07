# Building and distributing LidGlow

## Current release

`v0.2.2` ships an arm64 app for macOS 13+, a drag-to-Applications DMG with an offline installer, and a ZIP used by the one-command installer. The app's hardware support is much narrower than the OS/CPU requirement; installation does not imply a compatible illuminated logo.

The prebuilt files live in `dist/` so downloads work directly from the main branch without requiring GitHub CLI or a separate Release upload. They are small checked-in release artifacts. Build logs, test audio, historical source ZIPs, backups, personal defaults and machine-bound recovery files are excluded.

The checked-in release is **ad-hoc signed, not Developer ID signed or Apple-notarized**. Ad-hoc updates cannot reliably preserve TCC authorization. Do not promise zero prompts on new Macs or upgrades. Gatekeeper acceptance on a fresh Mac is not promised. SHA-256 and `codesign --verify` prove consistency/integrity, not publisher identity. Never remove quarantine or change system security to make an installer seem seamless.

## Rebuild

Use macOS and Apple's Command Line Tools:

```sh
./package.sh
(cd dist && shasum -a 256 -c SHA256SUMS)
```

The package script tests the pure signal engine and mock-only restoration path, builds with Apple's SDK, signs locally, validates the app, creates the disk image, and verifies the DMG. It does not exercise real hardware, capture audio, change permissions or modify login items. There are no downloaded build dependencies.

To preserve the exact app the user already tested/authorized, package it without rebuilding or re-signing:

```sh
./package.sh --app /Applications/LidGlow.app
```

The selected bundle must validate and have the expected identifier. Packaging copies its bytes unchanged. The installer skips an identical existing bundle and warns when an upgrade changes its code hash. These measures avoid unnecessary churn; they cannot repair a stale TCC record or turn ad-hoc signing into a stable developer identity.

Expected outputs:

- `build/LidGlow.app`
- `dist/LidGlow-0.2.2-macos-arm64.dmg`
- `dist/LidGlow-0.2.2-macos-arm64.zip`
- `dist/SHA256SUMS`

The Mach-O executable targets arm64 with minimum macOS 13. The private interface is guarded by runtime capability checks. Keep bundle ID `local.lidglow.lab` and the user recovery directory stable for upgrades. Do not add unrelated entitlements or blanket permissions: non-sandboxed system-output capture still requires native TCC consent.

## Developer ID signing and notarization

For a lower-friction public distribution, the maintainer needs an Apple Developer Program membership, an authorized **Developer ID Application** certificate with its private key, and existing notary credentials. These are not included in this repository. Do not commit signing credentials.

With that identity already installed, build with hardened runtime:

```sh
SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./package.sh
```

The optional signing path is provided but was not exercised for this release. Before distribution, use Apple's notarization service with an existing Keychain profile:

```sh
xcrun notarytool submit dist/LidGlow-0.2.2-macos-arm64.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple build/LidGlow.app
codesign --verify --strict build/LidGlow.app
```

After stapling, package that exact app with `SIGN_IDENTITY=... ./package.sh --app "$PWD/build/LidGlow.app"`. Do not use the default rebuilding path. Then notarize and staple the DMG:

```sh
xcrun notarytool submit dist/LidGlow-0.2.2-macos-arm64.dmg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/LidGlow-0.2.2-macos-arm64.dmg
xcrun stapler validate build/LidGlow.app
xcrun stapler validate dist/LidGlow-0.2.2-macos-arm64.dmg
spctl --assess --type execute --verbose build/LidGlow.app
```

Regenerate SHA256SUMS after **all** signing/stapling steps. Test a quarantined browser download on a separate Mac. Notarization does not grant screen/audio capture or login consent, does not guarantee hardware support, and Apple's service may reject software using unsupported/private interfaces.

## Release checklist

1. Keep Info.plist version, install.sh VERSION, filenames and download links in agreement.
2. Run `./test.sh`, `./package.sh`, checksum verification, and `./test_install.sh` on Apple Silicon after quitting LidGlow normally. Installer tests use a temporary destination and never launch the app.
3. Audit the exact Git staging list for secrets, local logs, device identities and recovery data.
4. Publish source and matching artifacts to the requested repository without force-pushing. Keep the installation command pointed at main.
5. Verify the remote commit, downloads and CI. Do not call notarization, fresh-machine launch or physical-hardware tests passed unless actually completed.

No signing certificate or notarization account is created/configured by these scripts. The app intentionally preserves its existing permissions explanation and asks only when Music/Auto is selected.
