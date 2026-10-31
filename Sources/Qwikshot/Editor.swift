import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Centres the canvas in the space left between the toolbar and the palette.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView, rect.width > 0 else { return rect }
        let magnification = frame.width / rect.width
        let top = contentInsets.top / magnification
        let bottom = contentInsets.bottom / magnification
        let visibleHeight = rect.height - top - bottom
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if visibleHeight > document.frame.height { rect.origin.y = -(top + (visibleHeight - document.frame.height) / 2) }
        return rect
    }
}

/// Routes the standard Edit and File menu actions to the canvas while it's frontmost.
private final class EditorWindow: NSWindow {
    weak var controller: EditorWindowController?

    @objc func copy(_ sender: Any?) { controller?.copyImage() }
    @objc(saveDocument:) func save(_ sender: Any?) { controller?.saveAs() }
}

private extension NSToolbarItem.Identifier {
    static let undo = Self("undo")
    static let redo = Self("redo")
    static let pin = Self("pin")
    static let copy = Self("copy")
    static let save = Self("save")
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static var open: [EditorWindowController] = []

    static func open(_ shot: Shot) {
        let controller = EditorWindowController(shot: shot)
        Self.open.append(controller)
        if let window = controller.window { DockPresence.track(window) }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.fit()
    }

    private let canvas: CanvasView
    private let shot: Shot
    private let model = EditorModel()
    private let scrollView = NSScrollView()
    private let palette: NSHostingView<ToolPalette>
    private var undoItem: NSToolbarItem?
    private var redoItem: NSToolbarItem?

    private init(shot: Shot) {
        self.shot = shot
        canvas = CanvasView(shot: shot)
        palette = NSHostingView(rootView: ToolPalette(model: model))

        let visible = (Capture.screenUnderMouse()?.visibleFrame.size) ?? NSSize(width: 1280, height: 800)
        let size = NSSize(width: min(max(canvas.frame.width + 96, 900), visible.width * 0.9),
                          height: min(max(canvas.frame.height + 200, 560), visible.height * 0.9))
        let window = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        window.title = "Qwikshot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 800, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.controller = self
        window.delegate = self

        let toolbar = NSToolbar(identifier: "editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbarStyle = .unified
        window.toolbar = toolbar

        buildContent(in: window)

        model.canvas = canvas
        canvas.onToolChange = { [weak self] tool in self?.model.tool = tool }
        canvas.onCanvasResize = { [weak self] in self?.fit() }
        canvas.onHistoryChange = { [weak self] in self?.refreshHistoryItems() }
        refreshHistoryItems()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent(in window: NSWindow) {
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        palette.sizingOptions = .intrinsicContentSize
        palette.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window.contentView else { return }
        content.addSubview(scrollView)
        content.addSubview(palette)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            palette.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            palette.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        window.makeFirstResponder(canvas)
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.undo, .redo, .flexibleSpace, .pin, .copy, .save]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case .undo:
            undoItem = item(identifier, "Undo", "arrow.uturn.backward", "Undo (⌘Z)", #selector(undo))
            undoItem?.autovalidates = false
            return undoItem
        case .redo:
            redoItem = item(identifier, "Redo", "arrow.uturn.forward", "Redo (⇧⌘Z)", #selector(redo))
            redoItem?.autovalidates = false
            return redoItem
        case .pin:
            return item(identifier, "Pin", "pin", "Pin to Screen", #selector(pin))
        case .copy:
            return item(identifier, "Copy", "doc.on.doc", "Copy (⌘C)", #selector(copyImage))
        case .save:
            let save = item(identifier, "Save", "square.and.arrow.down", "Save As… (⌘S)", #selector(saveAs))
            save.style = .prominent
            return save
        default:
            return nil
        }
    }

    private func item(_ identifier: NSToolbarItem.Identifier, _ label: String, _ symbol: String,
                      _ tip: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.toolTip = tip
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    private func refreshHistoryItems() {
        undoItem?.isEnabled = canvas.canUndo
        redoItem?.isEnabled = canvas.canRedo
    }

    // MARK: Layout

    /// Fits the image between the toolbar and the palette. The scroll view still runs
    /// under both, so a zoomed image passes beneath the glass.
    private func fit() {
        guard let content = window?.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let top = content.safeAreaInsets.top
        let bottom = palette.fittingSize.height + 16
        scrollView.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        let available = NSSize(width: content.bounds.width - 48, height: content.bounds.height - top - bottom - 24)
        scrollView.magnification = min(1, min(available.width / canvas.frame.width, available.height / canvas.frame.height))
    }

    // MARK: Actions

    @objc private func undo() { canvas.undo(nil) }
    @objc private func redo() { canvas.redo(nil) }

    @objc private func pin() {
        guard let image = canvas.flattened() else { return }
        let size = NSSize(width: CGFloat(image.width) / shot.scale, height: CGFloat(image.height) / shot.scale)
        PinWindow.pin(image: NSImage(cgImage: image, size: size))
    }

    @objc func copyImage() {
        guard let image = canvas.flattened() else { return }
        Store.copy(image, scale: shot.scale)
        Toast.show("Copied", symbol: "doc.on.doc.fill")
    }

    @objc func saveAs() {
        guard let image = canvas.flattened(), let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = Store.timestampedName(ext: "png")
        panel.directoryURL = Prefs.saveFolder
        panel.beginSheetModal(for: window) { [shot] response in
            guard response == .OK, let url = panel.url else { return }
            let type: UTType = url.pathExtension.lowercased() == "png" ? .png : .jpeg
            Store.write(image, scale: shot.scale, to: url, type: type)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) { fit() }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
