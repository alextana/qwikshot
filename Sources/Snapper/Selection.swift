import AppKit

/// Full-screen overlays over frozen display images, resolving to what the user picked.
@MainActor
final class SelectionSession {
    enum Mode { case area, window }
    enum Result {
        case area(DisplayShot, CGRect)
        case window(WindowTarget)
        case cancelled
    }

    private static var current: SelectionSession?

    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<Result, Never>?

    static func run(mode: Mode, shots: [DisplayShot], targets: [WindowTarget] = []) async -> Result {
        await withCheckedContinuation { continuation in
            let session = SelectionSession()
            session.continuation = continuation
            current = session
            session.show(mode: mode, shots: shots, targets: targets)
        }
    }

    private func show(mode: Mode, shots: [DisplayShot], targets: [WindowTarget]) {
        NSApp.activate(ignoringOtherApps: true)
        for shot in shots {
            let window = OverlayWindow(contentRect: shot.screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(shot.screen.frame, display: false)
            window.contentView = OverlayView(shot: shot, mode: mode, targets: targets, session: self)
            window.orderFrontRegardless()
            windows.append(window)
        }
        let active = Capture.screenUnderMouse()
        let key = windows.first { $0.frame == active?.frame } ?? windows.first
        key?.makeKeyAndOrderFront(nil)
        key?.makeFirstResponder(key?.contentView)
        NSCursor.crosshair.set()
    }

    fileprivate func finish(_ result: Result) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        continuation?.resume(returning: result)
        continuation = nil
        Self.current = nil
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    private let shot: DisplayShot
    private let mode: SelectionSession.Mode
    private let targets: [WindowTarget]
    private weak var session: SelectionSession?

    private var dragStart: NSPoint?
    private var cursor: NSPoint?
    private var hovered: WindowTarget?
    private lazy var pixelScale = CGFloat(shot.image.width) / shot.screen.frame.width

    init(shot: DisplayShot, mode: SelectionSession.Mode, targets: [WindowTarget], session: SelectionSession) {
        self.shot = shot
        self.mode = mode
        self.targets = targets
        self.session = session
        super.init(frame: NSRect(origin: .zero, size: shot.screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
                                       owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        if bounds.contains(point) { update(cursor: point) }
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { update(cursor: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { window?.makeKey(); update(cursor: convert(event.locationInWindow, from: nil)) }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        hovered = nil
        needsDisplay = true
    }

    private func update(cursor point: NSPoint) {
        cursor = point
        if mode == .window { hovered = target(at: point) }
        needsDisplay = true
    }

    private func viewRect(for target: WindowTarget) -> CGRect {
        Capture.appKitRect(fromGlobal: target.frame).offsetBy(dx: -shot.screen.frame.minX, dy: -shot.screen.frame.minY)
    }

    private func target(at point: NSPoint) -> WindowTarget? {
        targets.first { viewRect(for: $0).contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mode == .area { dragStart = point; cursor = point }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area else { return }
        let point = convert(event.locationInWindow, from: nil)
        cursor = NSPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .window {
            if let target = target(at: convert(event.locationInWindow, from: nil)) {
                session?.finish(.window(target))
            }
            return
        }
        guard let rect = selection, rect.width >= 3, rect.height >= 3 else {
            dragStart = nil
            needsDisplay = true
            return
        }
        session?.finish(.area(shot, rect.integral))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: session?.finish(.cancelled)                 // Esc
        case 36, 76:                                         // Return picks the whole display
            if mode == .area { session?.finish(.area(shot, bounds)) }
        default: super.keyDown(with: event)
        }
    }

    private var selection: CGRect? {
        guard let dragStart, let cursor else { return nil }
        return CGRect(x: min(dragStart.x, cursor.x), y: min(dragStart.y, cursor.y),
                      width: abs(dragStart.x - cursor.x), height: abs(dragStart.y - cursor.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(shot.image, in: bounds)

        let highlight = mode == .area ? selection : hovered.map { viewRect(for: $0) }
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.addRect(bounds)
        if let highlight { ctx.addRect(highlight) }
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        if let highlight {
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(highlight.insetBy(dx: -0.5, dy: -0.5))
        }

        guard let cursor else { return }
        if mode == .area {
            if let selection {
                label("\(Int(selection.width)) × \(Int(selection.height))", near: cursor)
            } else {
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
                ctx.setLineWidth(1)
                ctx.strokeLineSegments(between: [CGPoint(x: 0, y: cursor.y), CGPoint(x: bounds.width, y: cursor.y),
                                                 CGPoint(x: cursor.x, y: 0), CGPoint(x: cursor.x, y: bounds.height)])
                label("\(Int(cursor.x)), \(Int(bounds.height - cursor.y))", near: cursor)
            }
            drawLoupe(ctx, at: cursor)
        }
    }

    private func label(_ text: String, near point: NSPoint) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = string.size()
        var pill = CGRect(x: point.x + 14, y: point.y - size.height - 20, width: size.width + 14, height: size.height + 6)
        if pill.maxX > bounds.width { pill.origin.x = point.x - pill.width - 14 }
        if pill.minY < 0 { pill.origin.y = point.y + 14 }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        string.draw(at: CGPoint(x: pill.minX + 7, y: pill.minY + 3))
    }

    private func drawLoupe(_ ctx: CGContext, at point: NSPoint) {
        let side: CGFloat = 120
        let samplePixels: CGFloat = 15
        let sample = CGRect(x: point.x * pixelScale - samplePixels / 2,
                            y: (bounds.height - point.y) * pixelScale - samplePixels / 2,
                            width: samplePixels, height: samplePixels)
        guard let crop = shot.image.cropping(to: sample.integral) else { return }

        var frame = CGRect(x: point.x + 18, y: point.y + 18, width: side, height: side)
        if frame.maxX > bounds.width { frame.origin.x = point.x - side - 18 }
        if frame.maxY > bounds.height { frame.origin.y = point.y - side - 18 }

        ctx.saveGState()
        let circle = CGPath(ellipseIn: frame, transform: nil)
        ctx.addPath(circle)
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: frame)
        ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.8).cgColor)
        ctx.strokeLineSegments(between: [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.midX, y: frame.maxY),
                                         CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.midY)])
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(circle)
        ctx.strokePath()
    }
}
