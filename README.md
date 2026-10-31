# Qwikshot

A local menu bar screenshot tool for macOS 26 or later. Open source under the MIT license. No account needed, and the only
network use is checking for updates.

## Download

Get the latest zip from [Releases](https://github.com/alextana/qwikshot/releases), unzip it, and
move `Qwikshot.app` to `/Applications`. It needs macOS 26 or later on Apple silicon.

Qwikshot isn't notarized, so macOS blocks it the first time you open it. Go to System Settings >
Privacy & Security and choose Open Anyway. After that, use Check for Updates… in the menu.

## Build from source

```bash
./install.sh
```

This builds `Qwikshot.app`, replaces the copy in `/Applications`, and opens it. Run it again to
update. On first capture, turn on Qwikshot under Privacy & Security > Screen & System Audio
Recording, then reopen the app.

The first run creates a self-signed certificate, "Qwikshot Local Signing", in your login keychain.
Every build is signed with it, so macOS keeps the permission across updates. To build without
installing, run `./build.sh`, which signs ad hoc if the certificate doesn't exist.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘⇧3 | Capture the display under the cursor |
| ⌘⇧4 | Capture an area (Return selects the whole display, Esc cancels) |
| ⌘⇧5 | Capture a window |
| ⌘⇧6 | Start or stop recording an area to MP4 |
| ⌘⇧7 | Copy text from an area (OCR) |

⌘⇧3, ⌘⇧4 and ⌘⇧5 are also the macOS screenshot shortcuts, so turn those off under System Settings >
Keyboard > Keyboard Shortcuts > Screenshots. Shortcuts are set in
`AppDelegate.applicationDidFinishLaunching`.

## Editor

Keys: V select, A arrow, L line, R rectangle, O ellipse, P pen, H highlighter, T text, B pixelate,
F focus (blurs everything outside a rectangle), N numbered step, C crop. Shift constrains shapes and
lines. ⌘Z undo, ⇧⌘Z redo, ⌘C copy, ⌘S save.

## Files

- Captures: the last 30 are kept in `~/Library/Application Support/Qwikshot/History`.
- Saves and recordings: the folder chosen in Settings (Desktop by default).

## Test

```bash
.build/release/Qwikshot --render-test /tmp/qwikshot-test.png
```

Renders every annotation type, then checks focus blur, crop sizing, PNG DPI, and OCR. It needs no
permissions.

```bash
.build/release/Qwikshot --ui-snapshots /tmp/qwikshot-ui
```

Writes each window's layout to a PNG. Liquid Glass only composites on screen, so these show layout,
not the material.

## Release

1. Raise the number in `VERSION` and commit.
2. Run `Scripts/release.sh`.

This builds, signs and publishes a GitHub release, and every installed copy finds it through the
update feed in `build.sh`. Releases need the "Qwikshot Local Signing" certificate and the Sparkle
private key, both in the maintainer's login keychain. If you fork the project, generate your own
with `Scripts/setup-signing.sh` and Sparkle's `generate_keys`, then replace the feed URL and
`SUPublicEDKey` in `build.sh`.

## Design

The interface uses Liquid Glass through SwiftUI, with a native toolbar in the editor. Springs are
critically damped, panels leave the way they came, and Reduce Motion replaces movement with fades.
`Scripts/make-icon.swift` regenerates the app icon.
