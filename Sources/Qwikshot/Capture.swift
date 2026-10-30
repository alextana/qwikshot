import AppKit
import ScreenCaptureKit

/// A frozen image of one display, taken before the selection overlay appears.
struct DisplayShot {
    let screen: NSScreen
    let display: SCDisplay
    let image: CGImage
}

/// A window the user can pick, with its frame in the global top-left coordinate space.
struct WindowTarget {
    let window: SCWindow
    let frame: CGRect
    let scale: CGFloat
}

enum Capture {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private static func filter(for display: SCDisplay, in content: SCShareableContent) -> SCContentFilter {
        let ownApp = content.applications.filter { $0.processID == getpid() }
        return SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
    }

    static func recordingFilter(for display: SCDisplay, in content: SCShareableContent) -> SCContentFilter {
        filter(for: display, in: content)
    }

    static func freeze(_ screens: [NSScreen]) async throws -> [DisplayShot] {
        let content = try await content()
        var shots: [DisplayShot] = []
        for screen in screens {
            guard let id = displayID(of: screen),
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter(for: display, in: content), configuration: config)
            shots.append(DisplayShot(screen: screen, display: display, image: image))
        }
        return shots
    }

    /// Normal app windows, front to back. CGWindowList guarantees that order; SCShareableContent doesn't.
    static func windowTargets() async throws -> [WindowTarget] {
        let content = try await content()
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return info.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let window = byID[number],
                  window.windowLayer == 0,
                  window.owningApplication?.processID != getpid(),
                  window.frame.width > 40, window.frame.height > 40 else { return nil }
            let scale = screen(containing: window.frame)?.backingScaleFactor ?? 2
            return WindowTarget(window: window, frame: window.frame, scale: scale)
        }
    }

    static func capture(_ target: WindowTarget) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = Int(target.frame.width * target.scale)
        config.height = Int(target.frame.height * target.scale)
        config.showsCursor = false
        config.backgroundColor = .clear
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: target.window), configuration: config)
    }

    /// Converts a global top-left rect to the AppKit bottom-left space.
    static func appKitRect(fromGlobal rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func screen(containing globalRect: CGRect) -> NSScreen? {
        let rect = appKitRect(fromGlobal: globalRect)
        return NSScreen.screens.max {
            $0.frame.intersection(rect).area < $1.frame.intersection(rect).area
        }
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
