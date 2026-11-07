# How LidGlow Works: A Beginner's Guide

LidGlow is a small native macOS menu-bar app. It calculates a light level and asks macOS to apply it to a compatible logo-backlight device. Music mode uses system-output audio to decide when to pulse. Everything runs locally.

It cannot add a light to a Mac that does not have the required hardware. The current build targets Apple Silicon and macOS 13 or newer. The hardware interface is experimental and private, so a future macOS update can break it.

## 1. What actually controls the light?

There is no built-in Terminal command such as `lidglow set-brightness`. The app controls the light through Objective-C calls in [Hardware.m](Hardware.m).

First, it checks for this device-tree node with IOKit:

```text
IODeviceTree:/arm-io/pwm1/bklb-backlight
```

You can look for the device without changing anything:

```sh
ioreg -p IODeviceTree -r -n bklb-backlight
```

Finding a node alone does not prove that all required controls work. LidGlow also checks that it can read a valid brightness mapping and mode.

The app then loads Apple's private framework:

```text
/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness
```

It creates a `BrightnessSystemClient` and checks the method signatures before calling:

```objc
[client copyPropertyForKey:key];
[client setProperty:value forKey:key];
```

These are API calls inside the app, not commands to paste into Terminal. The relevant properties are:

- `LEPWMBrightnessNitsMapping`: the mapping that determines the requested logo-light level.
- `LEBacklightMode`: LidGlow writes `2` for a positive level and `0` for Off.
- `DisplayPowerStateEvent`: LidGlow writes `1` as part of applying or restoring settings. This is a private event; its wider display-power effects are not guaranteed.

For each update, the app computes a requested number of nits and supplies a two-row mapping with the same nits value in both rows. In plain terms, it asks for one fixed level rather than letting that mapping vary with its input. It repeats this with new levels to create animation.

The app does not call a display-brightness API or change the screen's brightness slider. It does use private system controls, which is why it should be treated as experimental.

## 2. How brightness and the lighting modes work

The app uses numbers from `0` to `1` internally: `0` means off and `1` means the original mapping's maximum. The Maximum brightness slider selects a fraction of that original maximum. The app never requests more than the original maximum it saved.

[main.m](main.m) calculates effects about 30 times per second. It skips very small changes to avoid unnecessary writes.

- **Breathe:** follows a smooth cosine wave using the selected breathing period. Its original behavior is unchanged; the mathematical wave can reach zero.
- **Music:** follows the audio detector, then adds a small minimum glow.
- **Auto · Breathe + Music:** breathes during silence and switches toward music when sound returns. It blends the two effects instead of switching abruptly.
- **Manual:** holds the selected brightness.
- **Off:** explicitly requests zero.
- **Restore / System control:** gives the original mapping and mode back to macOS.

For Music and Auto, the final calculation is:

```text
requested level = selected maximum × (0.01 + 0.99 × effect level)
```

For example, with a 60% maximum, the minimum is 0.6% of the original maximum and the peak is 60%. The floor is applied after Auto's blend, so silence, beat troughs and transitions all retain it. Setting the maximum to zero still turns the light off.

The 1% floor is a design choice. These numbers describe requested system values, not measured physical light. Ambient conditions and macOS limits can affect what you see.

## 3. How music becomes pulses

[AudioMeter.m](AudioMeter.m) uses Apple's public ScreenCaptureKit API. It configures an `SCStream` to receive system-output audio, requesting 48 kHz stereo, and registers an audio output only. It does not register a screen-video output or use the microphone. It does not save audio or send it over a network.

[Signal.c](Signal.c) processes short audio windows, normally about 5 milliseconds:

1. Measure overall energy and low-frequency energy separately for each channel.
2. Compare fast changes with slower recent averages.
3. Treat a strong new accent as a beat and generate a pulse.
4. Let the pulse fade quickly, while keeping sustained sound from repeatedly pinning the light at full brightness.

Beat sensitivity changes which accents qualify. It is not simply a volume multiplier. Separate channel analysis helps avoid losing bass when stereo channels have opposite phases.

The detector still reports zero for silence. The minimum glow is added later by the lighting code, so it does not trick Auto into thinking silence is music. Auto waits about 0.7 seconds of silence before leaving the active-audio state. The app also checks available output-device mute/volume information because captured audio can sometimes contain sound even while the speakers are muted.

## 4. How restoration protects the original settings

Before the first write in a control session, [Hardware.m](Hardware.m) re-reads the complete original mapping and mode, validates them, and saves a local recovery snapshot:

```text
~/Library/Application Support/LidGlowLab/recovery.plist
```

The snapshot is tied to the device and OS build. It must not be uploaded or copied to another Mac.

**Restore** and **Restore & Quit** put back the complete saved mapping and mode. The snapshot is removed only after restoration succeeds. If a previous session did not restore cleanly, the app asks about recovery before starting effects again.

Screen-off, sleep and lock pause effects and capture. [Lifecycle.c](Lifecycle.c) tracks these separately so one wake event does not resume effects while another pause reason remains. Once all known blockers clear, the app restores the old control session first, then resumes the chosen mode. A fresh launch always starts in Breathe.

There is no separate crash watchdog. A force-quit can leave the last requested level in place until recovery or system takeover, so use **Restore & Quit** normally.

## 5. Why macOS asks for recording permission

ScreenCaptureKit requires native authorization, which macOS may call **Screen & System Audio Recording**, even though LidGlow only consumes audio buffers.

The app's own explanation and macOS authorization are separate. Accepting the app's explanation does not grant system permission. A capture error stops effects and attempts to restore the original settings.

Current releases are ad-hoc signed, not Developer ID signed or notarized. Rebuilding changes the signature and can make an old recording authorization stop matching, even when Settings still shows an enabled switch. Follow the native permission flow for LidGlow only. The app and installer do not reset permissions, disable security, or grant themselves access.

## 6. Useful project commands

Run these from the repository directory on a compatible Mac with Apple's Command Line Tools installed:

```sh
./test.sh                         # Numerical and mock application tests
./build.sh                        # Build and verify build/LidGlow.app; do not launch
open "build/LidGlow.app"           # Launch the build; starts in Breathe
./package.sh                      # Test, build and create DMG/ZIP/checksums
(cd dist && shasum -a 256 -c SHA256SUMS)
```

To install a local build, first choose **Restore & Quit** in any running copy:

```sh
./install.sh --app "$PWD/build/LidGlow.app"
```

The installer verifies the bundle and keeps a backup when replacing a different installed app. It does not repair or reset recording permission.

For a read-only view of the current system mapping and mode, compile and run the included diagnostic:

```sh
mkdir -p build
xcrun clang -fobjc-arc readback.m -framework Foundation -o build/lidglow-readback
./build/lidglow-readback
```

This reads values; it does not control the light. Test logs and diagnostic output should stay local. Use the app's controls for changes so its checks and recovery snapshot are in place.

## 7. What the tests can prove

`test_signal.c` checks the math and audio detector. `test_effects.m` exercises the actual effect/mode code with fake audio and hardware, including the minimum-glow fix. Lifecycle and recovery tests cover their corresponding code paths. Packaging checks validate file integrity and signatures.

These tests do not prove physical appearance or fresh macOS recording authorization. The 0.2.2 package still needs device-specific real-audio and physical-light validation. See [TEST-RESULTS.md](TEST-RESULTS.md) and [DISTRIBUTION-TESTS.md](DISTRIBUTION-TESTS.md) for exactly what passed and what remains unverified.
