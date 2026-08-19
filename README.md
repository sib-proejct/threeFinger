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
