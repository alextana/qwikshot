import AppKit
import ServiceManagement
import SwiftUI

private struct SettingsView: View {
    @AppStorage(Prefs.copyAfterCapture) private var copyAfterCapture = true
    @AppStorage(Prefs.saveAfterCapture) private var saveAfterCapture = false
    @AppStorage(Prefs.showPreview) private var showPreview = true
    @AppStorage(Prefs.playSound) private var playSound = true
    @AppStorage(Prefs.previewSeconds) private var previewSeconds = 6.0
    @AppStorage(Prefs.recordClicks) private var recordClicks = true
    @State private var folder = Prefs.saveFolder
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("After capture") {
                Toggle("Copy to clipboard", isOn: $copyAfterCapture)
                Toggle("Save to folder", isOn: $saveAfterCapture)
                Toggle("Show floating preview", isOn: $showPreview)
                Stepper("Hide preview after \(Int(previewSeconds)) s", value: $previewSeconds, in: 2...30)
                Toggle("Play sound", isOn: $playSound)
            }
            Section("Saving") {
                LabeledContent("Folder") {
                    Button(folder.lastPathComponent, action: chooseFolder)
                }
            }
            Section("Recording") {
                Toggle("Show mouse clicks", isOn: $recordClicks)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 470)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            Prefs.saveFolder = url
            folder = url
        }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            created.title = "Qwikshot Settings"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
