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

    private static let shortcuts = [
        ("Capture Area", "⌥⇧4"), ("Capture Window", "⌥⇧5"), ("Capture Full Screen", "⌥⇧3"),
        ("Capture Text", "⌥⇧7"), ("Record Screen", "⌥⇧6"),
    ]

    var body: some View {
        Form {
            Section("After Capture") {
                Toggle("Copy to clipboard", isOn: $copyAfterCapture)
                Toggle("Save to folder", isOn: $saveAfterCapture)
                Toggle("Show preview", isOn: $showPreview)
                if showPreview {
                    LabeledContent("Keep preview for") {
                        Stepper("\(Int(previewSeconds)) seconds", value: $previewSeconds, in: 2...30)
                    }
                }
                Toggle("Play sound", isOn: $playSound)
            }
            Section("Saving") {
                LabeledContent("Save to") {
                    Button(folder.lastPathComponent, systemImage: "folder", action: chooseFolder)
                }
            }
            Section("Recording") {
                Toggle("Show mouse clicks", isOn: $recordClicks)
            }
            Section("Shortcuts") {
                ForEach(Self.shortcuts, id: \.0) { title, keys in
                    LabeledContent(title, value: keys)
                }
            }
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
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
        .animation(Motion.standard, value: showPreview)
        .frame(width: 460, height: 620)
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
        if let window { DockPresence.track(window) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
