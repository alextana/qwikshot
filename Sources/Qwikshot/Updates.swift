import AppKit
import Sparkle

/// In-app updates through Sparkle. Each release is verified against the
/// public key in Info.plist before it's installed.
@MainActor
final class Updates: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updates()

    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                               userDriverDelegate: self)

    /// A menu bar app is rarely frontmost, so scheduled checks shouldn't steal focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    func start() {
        controller.startUpdater()
    }

    @objc func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
