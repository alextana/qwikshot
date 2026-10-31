import AppKit
import SwiftUI

/// The floating thumbnails stacked in the bottom-left corner after each capture.
@MainActor
final class PreviewManager {
    static let shared = PreviewManager()

    private var panels: [PreviewPanel] = []

    func show(_ shot: Shot) {
        let panel = PreviewPanel(shot: shot) { [weak self] panel in self?.remove(panel) }
        panels.append(panel)
        layout(animated: false, placing: panel)
        panel.orderFrontRegardless()
        panel.present()
    }

    private func remove(_ panel: PreviewPanel) {
        panels.removeAll { $0 === panel }
        panel.exit()
        layout(animated: true)
    }

    private func layout(animated: Bool, placing new: PreviewPanel? = nil) {
        guard let screen = Capture.screenUnderMouse() else { return }
        var y = screen.visibleFrame.minY
        for panel in panels.reversed() {
            let origin = NSPoint(x: screen.visibleFrame.minX, y: y)
            if animated && panel !== new {
                panel.animator().setFrameOrigin(origin)
            } else {
                panel.setFrameOrigin(origin)
            }
            y += panel.frame.height - 12
        }
    }
}

@Observable
private final class PreviewState {
    var presented = false
    var hovering = false
}

private final class PreviewPanel: FloatingPanel {
    private static let margin: CGFloat = 20

    private let shot: Shot
    private let state = PreviewState()
    private let onClose: (PreviewPanel) -> Void
    private var dismissTimer: Timer?

    init(shot: Shot, onClose: @escaping (PreviewPanel) -> Void) {
        self.shot = shot
        self.onClose = onClose
        let imageWidth: CGFloat = 240
        let aspect = CGFloat(shot.image.height) / CGFloat(shot.image.width)
        let imageSize = NSSize(width: imageWidth, height: min(max(imageWidth * aspect, 96), 240))
        let inset = PreviewCard.inset + Self.margin
        super.init(size: NSSize(width: imageSize.width + inset * 2, height: imageSize.height + inset * 2))

        let card = PreviewCard(image: shot.nsImage, url: shot.url, imageSize: imageSize, state: state, actions: .init(
            copy: { [weak self] in self?.copyShot() },
            save: { [weak self] in self?.saveShot() },
            annotate: { [weak self] in self?.annotate() },
            pin: { [weak self] in self?.pin() },
            dismiss: { [weak self] in self?.dismiss() }))
        let host = PanelHostingView(rootView: card)
        host.onHover = { [weak self] hovering in self?.hoverChanged(hovering) }
        contentView = host
        scheduleDismiss()
    }

    func present() {
        DispatchQueue.main.async { [state] in
            withAnimation(Motion.standard) { state.presented = true }
        }
    }

    /// Leaves along the path it came in on.
    func exit() {
        dismissTimer?.invalidate()
        withAnimation(Motion.standard) { state.presented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.exitDelay) { [self] in orderOut(nil) }
    }

    private func hoverChanged(_ hovering: Bool) {
        withAnimation(Motion.standard) { state.hovering = hovering }
        if hovering {
            dismissTimer?.invalidate()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        let delay = UserDefaults.standard.double(forKey: Prefs.previewSeconds)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func dismiss() { onClose(self) }

    private func copyShot() {
        Store.copy(shot.image, scale: shot.scale)
        Toast.show("Copied", symbol: "doc.on.doc.fill")
        dismiss()
    }

    private func saveShot() {
        if let url = Store.saveToFolder(shot.image, scale: shot.scale) {
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "checkmark.circle.fill")
        }
        dismiss()
    }

    private func annotate() {
        EditorWindowController.open(shot)
        dismiss()
    }

    private func pin() {
        PinWindow.pin(image: shot.nsImage)
        dismiss()
    }
}

private struct PreviewCard: View {
    struct Actions {
        let copy, save, annotate, pin, dismiss: () -> Void
    }

    /// Glass around the image. The corner radii stay concentric: 22 − 8 = 14.
    static let inset: CGFloat = 8

    let image: NSImage
    let url: URL
    let imageSize: NSSize
    let state: PreviewState
    let actions: Actions

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageSize.width, height: imageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            .onTapGesture(count: 2, perform: actions.annotate)
            .overlay(alignment: .bottom) {
                if state.hovering {
                    controls.padding(8).transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if state.hovering {
                    Button("Dismiss", systemImage: "xmark", action: actions.dismiss)
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glass)
                        .padding(8)
                        .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
                }
            }
            .padding(Self.inset)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .offset(x: offset)
            .opacity(state.presented ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Slides in from the screen edge. With Reduce Motion it just fades.
    private var offset: CGFloat {
        state.presented || Motion.reduced ? 0 : -(imageSize.width + 60)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                control("Copy", "doc.on.doc", actions.copy)
                control("Save", "square.and.arrow.down", actions.save)
                control("Annotate", "pencil.tip", actions.annotate)
                control("Pin to Screen", "pin", actions.pin)
            }
        }
    }

    private func control(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)
            .controlSize(.large)
            .help(title)
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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PinView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.toolTip = "Double-click to close"
        contentView = view
        view.addCloseButton { [weak self] in self?.unpin() }
    }

    fileprivate func unpin() {
        orderOut(nil)
        Self.pins.removeAll { $0 === self }
    }
}

private final class PinView: NSImageView {
    private var closeButton: NSView?

    func addCloseButton(action: @escaping () -> Void) {
        let button = Button("Close", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)
        let host = PanelHostingView(rootView: button)
        host.frame = NSRect(x: 4, y: bounds.height - 44, width: 40, height: 40)
        host.autoresizingMask = [.minYMargin]
        host.isHidden = true
        addSubview(host)
        closeButton = host
    }

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton?.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton?.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (window as? PinWindow)?.unpin()
        } else {
            window?.performDrag(with: event)
        }
    }
}

@Observable
private final class ToastState {
    var visible = false
}

private struct ToastView: View {
    let message: String
    let symbol: String
    let state: ToastState

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .capsule)
            .scaleEffect(state.visible || Motion.reduced ? 1 : 0.92)
            .blur(radius: state.visible || Motion.reduced ? 0 : 8)
            .offset(y: state.visible || Motion.reduced ? 0 : 14)
            .opacity(state.visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A short confirmation at the bottom centre of the screen.
enum Toast {
    private static var panel: NSPanel?

    @MainActor
    static func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        panel?.orderOut(nil)
        let size = NSSize(width: 420, height: 100)
        let toast = FloatingPanel(size: size)
        toast.ignoresMouseEvents = true
        let state = ToastState()
        toast.contentView = NSHostingView(rootView: ToastView(message: message, symbol: symbol, state: state))
        if let screen = Capture.screenUnderMouse() {
            toast.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 12))
        }
        toast.orderFrontRegardless()
        panel = toast
        DispatchQueue.main.async {
            withAnimation(Motion.standard) { state.visible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard panel === toast else { return }
            withAnimation(Motion.standard) { state.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.exitDelay) {
                toast.orderOut(nil)
                if panel === toast { panel = nil }
            }
        }
    }
}
