import AppKit
import UniformTypeIdentifiers

/// Keeps the canvas centred when it's smaller than the viewport.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

/// Routes the standard Edit and File menu actions to the canvas while it's frontmost.
private final class EditorWindow: NSWindow {
    weak var controller: EditorWindowController?

    @objc func copy(_ sender: Any?) { controller?.copyImage() }
    @objc(saveDocument:) func save(_ sender: Any?) { controller?.saveAs() }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [EditorWindowController] = []

    static func open(_ shot: Shot) {
        let controller = EditorWindowController(shot: shot)
        Self.open.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.fit()
    }

    private let canvas: CanvasView
    private let shot: Shot
    private let scrollView = NSScrollView()
    private let tools = NSSegmentedControl()
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let colorWell = NSColorWell()
    private let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]

    private init(shot: Shot) {
        self.shot = shot
        canvas = CanvasView(shot: shot)

        let visible = (Capture.screenUnderMouse()?.visibleFrame.size) ?? NSSize(width: 1280, height: 800)
        let size = NSSize(width: min(max(renderedWidth(shot) + 80, 900), visible.width * 0.9),
                          height: min(renderedHeight(shot) + 140, visible.height * 0.9))
        let window = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.title = "Qwikshot"
        window.minSize = NSSize(width: 900, height: 320)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.controller = self
        window.delegate = self
        buildUI(in: window)

        canvas.onToolChange = { [weak self] tool in self?.tools.selectedSegment = tool.rawValue }
        canvas.onCanvasResize = { [weak self] in self?.fit() }
        canvas.onHistoryChange = { [weak self] in self?.refreshHistoryButtons() }
        refreshHistoryButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(in window: NSWindow) {
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        tools.segmentCount = Tool.allCases.count
        tools.trackingMode = .selectOne
        tools.target = self
        tools.action = #selector(toolChanged)
        for tool in Tool.allCases {
            tools.setImage(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: "\(tool)"), forSegment: tool.rawValue)
            tools.setWidth(32, forSegment: tool.rawValue)
            tools.setToolTip("\(tool) (\(tool.key.uppercased()))", forSegment: tool.rawValue)
        }
        tools.selectedSegment = canvas.tool.rawValue
        toolbar.addArrangedSubview(tools)

        let swatches = NSStackView()
        swatches.spacing = 4
        for (index, color) in palette.enumerated() {
            let swatch = NSButton(title: "", target: self, action: #selector(swatchPicked))
            swatch.tag = index
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 8
            swatch.layer?.borderWidth = 1
            swatch.layer?.borderColor = NSColor.separatorColor.cgColor
            swatch.widthAnchor.constraint(equalToConstant: 16).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true
            swatches.addArrangedSubview(swatch)
        }
        toolbar.addArrangedSubview(swatches)

        colorWell.color = canvas.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.colorWellStyle = .minimal
        colorWell.widthAnchor.constraint(equalToConstant: 24).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        toolbar.addArrangedSubview(colorWell)

        let slider = NSSlider(value: canvas.strokeWidth, minValue: 1, maxValue: 12, target: self, action: #selector(widthChanged))
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        slider.toolTip = "Stroke and text size"
        toolbar.addArrangedSubview(slider)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        toolbar.addArrangedSubview(spacer)

        configure(undoButton, symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)", action: #selector(undo))
        configure(redoButton, symbol: "arrow.uturn.forward", tip: "Redo (⇧⌘Z)", action: #selector(redo))
        toolbar.addArrangedSubview(undoButton)
        toolbar.addArrangedSubview(redoButton)

        let pinButton = NSButton(), copyButton = NSButton(), saveButton = NSButton()
        configure(pinButton, symbol: "pin", tip: "Pin to screen", action: #selector(pin))
        configure(copyButton, symbol: "doc.on.doc", tip: "Copy (⌘C)", action: #selector(copyImage))
        configure(saveButton, symbol: "square.and.arrow.down", tip: "Save As… (⌘S)", action: #selector(saveAs))
        toolbar.addArrangedSubview(pinButton)
        toolbar.addArrangedSubview(copyButton)
        toolbar.addArrangedSubview(saveButton)

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
        scrollView.backgroundColor = NSColor(white: 0.16, alpha: 1)
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window.contentView else { return }
        content.addSubview(toolbar)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.makeFirstResponder(canvas)
    }

    private func configure(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = tip
    }

    private func fit() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let view = scrollView.contentSize
        let canvasSize = canvas.frame.size
        let padded = min((view.width - 32) / canvasSize.width, (view.height - 32) / canvasSize.height)
        scrollView.magnification = min(1, padded)
    }

    private func refreshHistoryButtons() {
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
    }

    @objc private func toolChanged() {
        canvas.tool = Tool(rawValue: tools.selectedSegment) ?? .select
        window?.makeFirstResponder(canvas)
    }

    @objc private func swatchPicked(_ sender: NSButton) {
        canvas.color = palette[sender.tag]
        colorWell.color = palette[sender.tag]
    }

    @objc private func colorChanged() { canvas.color = colorWell.color }
    @objc private func widthChanged(_ sender: NSSlider) { canvas.strokeWidth = CGFloat(sender.doubleValue) }
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
        Toast.show("Copied to clipboard")
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

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}

private func renderedWidth(_ shot: Shot) -> CGFloat { CGFloat(shot.image.width) / shot.scale }
private func renderedHeight(_ shot: Shot) -> CGFloat { CGFloat(shot.image.height) / shot.scale }
