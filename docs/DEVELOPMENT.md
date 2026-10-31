# Developing Qwikshot

You need macOS 26 or later and Xcode 26 or later.

## Build and install

```bash
./install.sh
```

This builds `Qwikshot.app`, replaces the copy in `/Applications`, and opens it. Run it again to
update. On first capture, turn on Qwikshot under Privacy & Security > Screen & System Audio
Recording, then reopen the app.

The first run creates a self-signed certificate, "Qwikshot Local Signing", in your login keychain.
Every build is signed with it, so macOS keeps the permission across updates. To build without
installing, run `./build.sh`, which signs ad hoc if the certificate doesn't exist.

## Test

```bash
.build/release/Qwikshot --render-test /tmp/qwikshot-test.png
```

Renders every annotation type, then checks the Dock icon, focus blur, crop sizing, PNG DPI, and OCR.
It needs no permissions.

```bash
.build/release/Qwikshot --ui-snapshots /tmp/qwikshot-ui
```

Writes each window's layout to a PNG. Liquid Glass only composites on screen, so these show layout,
not the material.

## Images

- `--readme-art docs/images` redraws the README's example images with the annotation renderer.
- `Scripts/make-icon.swift` redraws the app icon.

## Release

1. Raise the number in `VERSION` and commit.
2. Run `Scripts/release.sh`.

This builds, signs and publishes a GitHub release, and every installed copy finds it through the
update feed in `build.sh`. Releases need the "Qwikshot Local Signing" certificate and the Sparkle
private key, both in the maintainer's login keychain.

If you fork the project, generate your own with `Scripts/setup-signing.sh` and Sparkle's
`generate_keys`, then replace the feed URL and `SUPublicEDKey` in `build.sh`.

## Design

The interface uses Liquid Glass through SwiftUI, with a native toolbar in the editor. Springs are
critically damped, panels leave the way they came, and Reduce Motion replaces movement with fades.

Shortcuts are set in `AppDelegate.applicationDidFinishLaunching`.
