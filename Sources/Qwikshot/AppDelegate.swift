import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import Vision

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private var busy = false
    private let recentMenu = NSMenu()
    private var recordItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-test"), arguments.indices.contains(index + 1) {
            let passed = SelfTest.run(output: URL(fileURLWithPath: arguments[index + 1]))
            exit(passed ? 0 : 1)
        }

        if let index = arguments.firstIndex(of: "--ui-snapshots"), arguments.indices.contains(index + 1) {
            SelfTest.snapshotUI(folder: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
            return
        }

        NSApp.mainMenu = makeMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setStatusIcon(recording: false)
        statusItem.menu = makeStatusMenu()

        let modifiers = optionKey | shiftKey
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: modifiers) { [weak self] in self?.captureFullscreen() }
        HotKeys.shared.register(keyCode: kVK_ANSI_4, modifiers: modifiers) { [weak self] in self?.captureArea() }
        HotKeys.shared.register(keyCode: kVK_ANSI_5, modifiers: modifiers) { [weak self] in self?.captureWindow() }
        HotKeys.shared.register(keyCode: kVK_ANSI_6, modifiers: modifiers) { [weak self] in self?.toggleRecording() }
        HotKeys.shared.register(keyCode: kVK_ANSI_7, modifiers: modifiers) { [weak self] in self?.captureText() }

        recorder.onFinish = { [weak self] result in self?.recordingFinished(result) }
        Updates.shared.start()

        if let index = arguments.firstIndex(of: "--edit"), arguments.indices.contains(index + 1),
           let shot = Store.load(URL(fileURLWithPath: arguments[index + 1])) {
            EditorWindowController.open(shot)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockPresence.bringForward()
        return false
    }

    // MARK: Menus

    /// Shown while a window puts the app in the Dock. At other times it's still what
    /// makes ⌘Z, ⌘C and ⌘V work.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(Updates.checkForUpdates), keyEquivalent: "").target = Updates.shared
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Qwikshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Qwikshot")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        return main
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        addCapture(to: menu, "Capture Area", "viewfinder", "4", #selector(captureArea))
        addCapture(to: menu, "Capture Window", "macwindow", "5", #selector(captureWindow))
        addCapture(to: menu, "Capture Full Screen", "display", "3", #selector(captureFullscreen))
        addCapture(to: menu, "Capture Text", "text.viewfinder", "7", #selector(captureText))
        menu.addItem(.separator())
        recordItem = addCapture(to: menu, "Record Screen", "record.circle", "6", #selector(toggleRecording))
        menu.addItem(.separator())

        menu.addItem(withTitle: "Open Image…", action: #selector(openImage), keyEquivalent: "").target = self
        recentMenu.delegate = self
        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Check for Updates…", action: #selector(Updates.checkForUpdates), keyEquivalent: "").target = Updates.shared
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Qwikshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @discardableResult
    private func addCapture(to menu: NSMenu, _ title: String, _ symbol: String, _ key: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.keyEquivalentModifierMask = [.option, .shift]
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let files = Store.recent()
        if files.isEmpty {
            menu.addItem(withTitle: "No Captures Yet", action: nil, keyEquivalent: "")
        }
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Qwikshot ", with: "")
            let item = menu.addItem(withTitle: name, action: #selector(openRecent), keyEquivalent: "")
            item.target = self
            item.representedObject = url
        }
    }

    private func setStatusIcon(recording: Bool) {
        let symbol = recording ? "stop.circle.fill" : "camera.viewfinder"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Qwikshot")
        image?.isTemplate = !recording
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
    }

    // MARK: Actions

    /// Runs one capture flow at a time, and reports failures in an alert.
    private func perform(_ flow: @escaping () async throws -> Void) {
        guard !busy, !recorder.isRecording else { return }
        guard ensurePermission() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await flow()
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func ensurePermission() -> Bool {
        if Capture.hasPermission() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Qwikshot needs Screen Recording permission"
        alert.informativeText = "Turn on Qwikshot under Privacy & Security > Screen & System Audio Recording, then reopen the app."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    @objc private func captureArea() {
        perform { [self] in
            guard let (image, scale) = try await pickArea() else { return }
            deliver(image, scale: scale)
        }
    }

    @objc private func captureFullscreen() {
        perform { [self] in
            guard let screen = Capture.screenUnderMouse(),
                  let shot = try await Capture.freeze([screen]).first else { return }
            deliver(shot.image, scale: screen.backingScaleFactor)
        }
    }

    @objc private func captureWindow() {
        perform { [self] in
            let shots = try await Capture.freeze(NSScreen.screens)
            let targets = try await Capture.windowTargets()
            guard case .window(let target) = await SelectionSession.run(mode: .window, shots: shots, targets: targets) else { return }
            deliver(try await Capture.capture(target), scale: target.scale)
        }
    }

    @objc private func captureText() {
        perform { [self] in
            guard let (image, _) = try await pickArea() else { return }
            let text = try await recognizeText(in: image)
            if text.isEmpty {
                Toast.show("No text found", symbol: "text.magnifyingglass")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Toast.show("Copied \(text.count) characters", symbol: "doc.on.doc.fill")
            }
        }
    }

    @objc private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        perform { [self] in
            let shots = try await Capture.freeze(NSScreen.screens)
            guard case .area(let shot, let rect) = await SelectionSession.run(mode: .area, shots: shots) else { return }
            try await recorder.start(shot: shot, rect: rect)
            setStatusIcon(recording: true)
            recordItem.title = "Stop Recording"
        }
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        setStatusIcon(recording: false)
        recordItem.title = "Record Screen"
        switch result {
        case .success(let url):
            Toast.show("Recording saved")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failure(let error):
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let shot = Store.load(url) {
            EditorWindowController.open(shot)
        }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL, let shot = Store.load(url) {
            EditorWindowController.open(shot)
        }
    }

    @objc private func showSettings() { SettingsWindow.show() }

    // MARK: Capture helpers

    private func pickArea() async throws -> (CGImage, CGFloat)? {
        let shots = try await Capture.freeze(NSScreen.screens)
        guard case .area(let shot, let rect) = await SelectionSession.run(mode: .area, shots: shots) else { return nil }
        let scale = CGFloat(shot.image.width) / shot.screen.frame.width
        let pixels = CGRect(x: rect.minX * scale, y: (shot.screen.frame.height - rect.maxY) * scale,
                            width: rect.width * scale, height: rect.height * scale)
        guard let image = shot.image.cropping(to: pixels.integral) else { return nil }
        return (image, scale)
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached { try OCR.text(in: image) }.value
    }

    private func deliver(_ image: CGImage, scale: CGFloat) {
        guard let shot = Store.recordInHistory(image: image, scale: scale) else { return }
        if Prefs.flag(Prefs.playSound) { NSSound(named: "Tink")?.play() }
        if Prefs.flag(Prefs.copyAfterCapture) { Store.copy(image, scale: scale) }
        if Prefs.flag(Prefs.saveAfterCapture) { Store.saveToFolder(image, scale: scale) }
        if Prefs.flag(Prefs.showPreview) { PreviewManager.shared.show(shot) }
    }
}

enum OCR {
    static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
