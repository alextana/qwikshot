import AppKit

/// The floating thumbnails stacked in the bottom-left corner after each capture.
@MainActor
final class PreviewManager {
    static let shared = PreviewManager()

    private var panels: [PreviewPanel] = []

    func show(_ shot: Shot) {
        let panel = PreviewPanel(shot: shot) { [weak self] panel in self?.remove(panel) }
        panels.append(panel)
        layout()
        panel.orderFrontRegardless()
    }

    private func remove(_ panel: PreviewPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
        layout()
    }

    private func layout() {
        guard let screen = Capture.screenUnderMouse() else { return }
        var y = screen.visibleFrame.minY + 16
        for panel in panels.reversed() {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 16, y: y))
            y += panel.frame.height + 10
        }
    }
}

private final class PreviewPanel: NSPanel {
    init(shot: Shot, onClose: @escaping (PreviewPanel) -> Void) {
        let width: CGFloat = 260
        let aspect = CGFloat(shot.image.height) / CGFloat(shot.image.width)
        let size = NSSize(width: width, height: min(max(width * aspect, 110), 260))
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = PreviewView(shot: shot, panel: self, onClose: onClose)
    }

    override var canBecomeKey: Bool { false }
}

private final class PreviewView: NSView, NSDraggingSource {
    private let shot: Shot
    private weak var panel: PreviewPanel?
    private let onClose: (PreviewPanel) -> Void
    private let controls = NSStackView()
    private var dismissTimer: Timer?
    private var mouseDownPoint: NSPoint?

    init(shot: Shot, panel: PreviewPanel, onClose: @escaping (PreviewPanel) -> Void) {
        self.shot = shot
        self.panel = panel
        self.onClose = onClose
        super.init(frame: panel.contentRect(forFrameRect: panel.frame))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let imageView = NSImageView(frame: bounds)
        imageView.image = shot.nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        controls.orientation = .horizontal
        controls.spacing = 6
        controls.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        controls.layer?.cornerRadius = 8
        controls.isHidden = true
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addControl("doc.on.doc", "Copy", #selector(copyShot))
        addControl("square.and.arrow.down", "Save", #selector(saveShot))
        addControl("pencil.tip.crop.circle", "Annotate", #selector(annotate))
        addControl("pin", "Pin to screen", #selector(pin))
        addControl("xmark", "Dismiss", #selector(dismiss))

        scheduleDismiss()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func addControl(_ symbol: String, _ tip: String, _ action: Selector) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .white
        button.toolTip = tip
        controls.addArrangedSubview(button)
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        let delay = UserDefaults.standard.double(forKey: Prefs.previewSeconds)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        controls.isHidden = false
        dismissTimer?.invalidate()
    }

    override func mouseExited(with event: NSEvent) {
        controls.isHidden = true
        scheduleDismiss()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        if event.clickCount == 2 { annotate() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let item = NSDraggingItem(pasteboardWriter: shot.url as NSURL)
        item.setDraggingFrame(bounds, contents: shot.nsImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    @objc private func copyShot() {
        Store.copy(shot.image, scale: shot.scale)
        Toast.show("Copied to clipboard")
        dismiss()
    }

    @objc private func saveShot() {
        if let url = Store.saveToFolder(shot.image, scale: shot.scale) {
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
        }
        dismiss()
    }

    @objc private func annotate() {
        EditorWindowController.open(shot)
        dismiss()
    }

    @objc private func pin() {
        PinWindow.pin(image: shot.nsImage)
        dismiss()
    }

    @objc private func dismiss() {
        dismissTimer?.invalidate()
        if let panel { onClose(panel) }
    }
}

/// An image floating above everything. Drag to move, double-click to close.
final class PinWindow: NSPanel {
    private static var pins: [PinWindow] = []

    static func pin(image: NSImage) {
        let window = PinWindow(image: image)
        pins.append(window)
        window.center()
        window.orderFrontRegardless()
    }

    private init(image: NSImage) {
        super.init(contentRect: NSRect(origin: .zero, size: image.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.toolTip = "Double-click to close"
        contentView = view
    }

    fileprivate func unpin() {
        orderOut(nil)
        Self.pins.removeAll { $0 === self }
    }
}

private final class PinView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (window as? PinWindow)?.unpin()
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// A short confirmation at the bottom centre of the screen.
enum Toast {
    private static var panel: NSPanel?

    @MainActor
    static func show(_ message: String) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 32, height: 36)
        let toast = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.level = .floating
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.ignoresMouseEvents = true
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        content.layer?.cornerRadius = 10
        label.setFrameOrigin(NSPoint(x: 16, y: (size.height - label.frame.height) / 2))
        content.addSubview(label)
        toast.contentView = content
        if let screen = Capture.screenUnderMouse() {
            toast.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                         y: screen.visibleFrame.minY + 40))
        }
        toast.orderFrontRegardless()
        panel = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if panel === toast {
                toast.orderOut(nil)
                panel = nil
            }
        }
    }
}
