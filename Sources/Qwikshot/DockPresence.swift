import AppKit

/// Qwikshot lives in the menu bar, but a window needs a way back after ⌘Tab.
/// While any tracked window is open, the app joins the Dock and the app switcher.
@MainActor
enum DockPresence {
    private static var windows: [NSWindow] = []
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func track(_ window: NSWindow) {
        guard !windows.contains(window) else { return }
        windows.append(window)
        NSApp.setActivationPolicy(.regular)

        let id = ObjectIdentifier(window)
        observers[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: window, queue: nil) { _ in
            MainActor.assumeIsolated {
                windows.removeAll { $0 === window }
                if let observer = observers.removeValue(forKey: id) {
                    NotificationCenter.default.removeObserver(observer)
                }
                if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    /// Answers a click on the Dock icon, including when the window is minimized.
    static func bringForward() {
        guard let window = windows.last else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}
