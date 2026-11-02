import AppKit
import SwiftUI

/// Shown once on first launch, and from the menu bar after that. macOS doesn't let an
/// app turn off its shortcuts, so this checks them and sends the user to the right page.
private struct SetupView: View {
    @State private var hasPermission = Capture.hasPermission()
    @State private var heldBySystem = CaptureShortcut.heldBySystem()

    private let check = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Allow Screen Recording") {
                    if hasPermission {
                        status("Qwikshot can capture your screen", done: true)
                    } else {
                        status("Turn on Qwikshot, then reopen the app", done: false)
                        Button("Open Screen Recording Settings", action: openPrivacy)
                    }
                }
                Section("Turn Off the macOS Shortcuts") {
                    if heldBySystem.isEmpty {
                        status("The macOS screenshot shortcuts are off", done: true)
                    } else {
                        status("macOS still uses \(heldBySystem.joined(separator: ", ")), so Qwikshot won't open",
                               done: false)
                        Text("In Keyboard, click Keyboard Shortcuts, choose Screenshots, and untick them.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Keyboard Settings", action: openKeyboard)
                    }
                }
                Section("Capture") {
                    ForEach(CaptureShortcut.all, id: \.keyCode) { shortcut in
                        LabeledContent(shortcut.title, value: shortcut.keys)
                    }
                }
                Section("After a Capture") {
                    Text("Your shot goes to the clipboard, ready to paste, and a preview appears. Double-click the preview to mark it up in the editor. You can change what happens in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Open this again from the menu bar icon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(Motion.standard, value: heldBySystem)
        .animation(Motion.standard, value: hasPermission)
        .frame(width: 460, height: 720)
        // The fixes happen in System Settings, so the marks follow it while it's open.
        .onReceive(check) { _ in
            hasPermission = Capture.hasPermission()
            heldBySystem = CaptureShortcut.heldBySystem()
        }
    }

    private func status(_ text: String, done: Bool) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(done ? .green : .orange)
        }
    }

    private func openPrivacy() {
        CGRequestScreenCaptureAccess()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openKeyboard() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}

@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: SetupView()))
            created.title = "Set Up Qwikshot"
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
