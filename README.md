# ThreeFingerMiddleClick

Personal macOS utility that converts a **three-finger tap or physical click** on
the built-in trackpad into a middle mouse click (scroll-wheel click).

## What it does

- Detects raw trackpad frames with `MultitouchSupport.framework`, opened at runtime.
- Accepts only an exact three-finger tap: all three touches must release within
  220 ms, their release may be spread across at most 80 ms, their centroid may
  move at most `0.020`, and any fourth touch cancels the gesture.
- Converts a physical three-finger trackpad click from left-click down/up events
  into middle-button down/up events, suppressing the original left click.
- Posts a Core Graphics middle-click at the current cursor location.
- Provides a small menu-bar menu for Enabled, Launch at Login, and Quit.

`MultitouchSupport` is a private macOS framework. This is deliberately a
personal-use utility and may need adjustment after macOS updates.

## Privacy and security

- The app reads raw built-in-trackpad contact frames only while **Enabled**.
  It installs its global left-click event filter only while the feature is
  running, and removes it when disabled or when the app quits.
- Contact positions, mouse events, and diagnostics are not written to files or
  sent over the network. The only persisted values are the Enabled / Dock-icon
  preferences and aggregate diagnostics shown in the status window.
- Accessibility permission is required because the app suppresses a qualifying
  physical left click and posts a middle click in its place. Review that
  permission before granting it, and disable the app when it is not needed.
- `MultitouchSupport` is a private, unsupported framework. Its ABI may change
  in a macOS update; this app is not suitable for the Mac App Store and Apple
  does not guarantee its continued operation.

ThreeFingerMiddleClick is independent software and is not affiliated with,
endorsed by, or supported by Apple.

## Build

Requirements: Xcode Command Line Tools, Rust, and an Apple-silicon Mac running
macOS 13 or later.

```sh
brew install rust
make app
open dist/ThreeFingerMiddleClick.app
```

The built app is at `dist/ThreeFingerMiddleClick.app`. On first launch, macOS
will ask for Accessibility permission; allow it under **System Settings →
Privacy & Security → Accessibility** so the app can post the middle-click.

To create a compressed disk image for storage or transfer:

```sh
make dmg
```

This writes `dist/ThreeFingerMiddleClick.dmg`.

## Public distribution

The default build uses an ad-hoc signature, which is appropriate only for a
local build. Do not distribute that DMG from a website. For a public release,
sign it with a Developer ID certificate, enable the hardened runtime (handled
by the build script for a Developer ID identity), and notarize the DMG:

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' make dmg
xcrun notarytool submit dist/ThreeFingerMiddleClick.dmg \
  --keychain-profile 'notary-profile' --wait
xcrun stapler staple dist/ThreeFingerMiddleClick.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 dist/ThreeFingerMiddleClick.dmg
```

The Developer ID certificate and `notary-profile` must belong to the release
publisher. Publish a SHA-256 checksum alongside every DMG, retain the source
and release tag that produced it, and test the stapled DMG on a clean Mac.
Notarization is a security check, not a guarantee that an unsupported private
framework will keep working in future macOS releases.

## Install from the DMG

1. Double-click `dist/ThreeFingerMiddleClick.dmg`.
2. Drag `ThreeFingerMiddleClick.app` onto the `Applications` shortcut shown in
   the disk-image window. Running the app directly from the DMG does not install it.
3. Eject the `ThreeFingerMiddleClick` disk image, then open
   **Applications → ThreeFingerMiddleClick**.
4. If macOS blocks the first launch, Control-click the app in Finder and choose
   **Open**. Allow **Accessibility** access when prompted.
5. A status window opens on launch. It shows whether the engine is running,
   Accessibility permission, received input frames, active fingers, and generated
   middle clicks. It also provides **Enabled** and **Launch at Login** controls.
6. Closing the window leaves the app running. Reopen it from the `3F` item in
   the upper-right menu bar. The Dock icon is hidden by default; toggle
   **Show Dock Icon** in the `3F` menu if you want it visible.

## Development checks

```sh
make test
swiftc -parse-as-library -typecheck -target arm64-apple-macos13.0 macos/ThreeFingerMiddleClickApp.swift
```

The three gesture thresholds are intentionally source constants in
`src/gesture.rs`; there is no settings window.

If Swift reports that its SDK and compiler versions do not match, install or
select a matching Xcode / Command Line Tools pair before building the app.

## License

This project is released under the [MIT License](LICENSE). It does not bundle
Apple frameworks or Apple source code. If you contribute code or assets copied
from elsewhere, you are responsible for preserving their required notices and
licenses.
