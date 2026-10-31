# Qwikshot

A local menu bar screenshot tool for macOS 26 or later. No account, no network access.

## Build

```bash
./build.sh
```

This produces `Qwikshot.app`. Move it to `/Applications` and open it. On first capture, turn on
Qwikshot under Privacy & Security > Screen & System Audio Recording, then reopen the app.

The app is signed ad hoc, so macOS treats each rebuild as a new app. After rebuilding, remove
Qwikshot from that permission list and add it again.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥⇧3 | Capture the display under the cursor |
| ⌥⇧4 | Capture an area (Return selects the whole display, Esc cancels) |
| ⌥⇧5 | Capture a window |
| ⌥⇧6 | Start or stop recording an area to MP4 |
| ⌥⇧7 | Copy text from an area (OCR) |

Shortcuts are set in `AppDelegate.applicationDidFinishLaunching`.

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

## Design

The interface uses Liquid Glass through SwiftUI, with a native toolbar in the editor. Springs are
critically damped, panels leave the way they came, and Reduce Motion replaces movement with fades.
`Scripts/make-icon.swift` regenerates the app icon.
