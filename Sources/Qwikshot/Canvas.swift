import AppKit

/// The undoable state of an editing session.
private struct Document {
    var annotations: [Annotation] = []
    var crop: CGRect?
}

final class CanvasView: NSView, NSTextFieldDelegate {
    let renderer: Renderer

    var tool: Tool = .arrow {
        didSet {
            selectedID = nil
            commitText()
            window?.invalidateCursorRects(for: self)
            onToolChange?(tool)
        }
    }
    var color: NSColor = .systemRed { didSet { restyleSelection() } }
    var strokeWidth: CGFloat = 4 { didSet { restyleSelection() } }
    var onToolChange: ((Tool) -> Void)?
    var onCanvasResize: (() -> Void)?
    var onHistoryChange: (() -> Void)?

    private var document = Document()
    private var undoStack: [Document] = []
    private var redoStack: [Document] = []

    private var draft: Annotation?
    private var cropDraft: (start: CGPoint, current: CGPoint)?
    private var selectedID: UUID?
    private var dragLast: CGPoint?
    private var dragHandle: KeyPath<Annotation, CGPoint>?
    private var dragMoved = false
    private var textField: NSTextField?
    private var editingTextID: UUID?

    init(shot: Shot) {
        renderer = Renderer(base: shot.image, scale: shot.scale)
        super.init(frame: NSRect(origin: .zero, size: renderer.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The image sits on the window like a sheet of paper. An explicit path keeps redraws fast.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowPath = CGPath(rect: CGRect(origin: .zero, size: newSize), transform: nil)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func flattened() -> CGImage? {
        commitText()
        return renderer.flatten(document.annotations, crop: document.crop)
    }

    // MARK: History

    private func checkpoint() {
        undoStack.append(document)
        redoStack.removeAll()
        onHistoryChange?()
    }

    @objc func undo(_ sender: Any?) {
        commitText()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        apply(previous)
    }

    @objc func redo(_ sender: Any?) {
        commitText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        apply(next)
    }

    private func apply(_ state: Document) {
        let cropChanged = state.crop != document.crop
        document = state
        selectedID = nil
        if cropChanged { resizeToCrop() }
        onHistoryChange?()
        needsDisplay = true
    }

    private func resizeToCrop() {
        setFrameSize(document.crop?.size ?? renderer.size)
        onCanvasResize?()
    }

    // MARK: Geometry

    private var origin: CGPoint { document.crop?.origin ?? .zero }

    private func documentPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }

    /// With Shift held: squares for shapes, 45° steps for lines.
    private func constrained(_ point: CGPoint, from start: CGPoint, tool: Tool, event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift) else { return point }
        let dx = point.x - start.x, dy = point.y - start.y
        switch tool {
        case .rectangle, .ellipse, .pixelate, .focus:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        case .arrow, .line:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        default:
            return point
        }
    }

    private var selectedIndex: Int? {
        document.annotations.firstIndex { $0.id == selectedID }
    }

    private func handle(at point: CGPoint, of item: Annotation) -> KeyPath<Annotation, CGPoint>? {
        guard item.tool.usesTwoPoints else { return nil }
        if hypot(point.x - item.a.x, point.y - item.a.y) < 9 { return \.a }
        if hypot(point.x - item.b.x, point.y - item.b.y) < 9 { return \.b }
        return nil
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let point = documentPoint(event)
        dragMoved = false

        switch tool {
        case .select:
            mouseDownSelecting(at: point, event: event)
        case .crop:
            cropDraft = (point, point)
        case .text:
            beginText(at: point, editing: nil)
        case .step:
            let next = (document.annotations.map(\.number).max() ?? 0) + 1
            checkpoint()
            document.annotations.append(Annotation(tool: .step, a: point, b: point, color: color,
                                                   width: strokeWidth, number: next))
        case .pen, .highlighter:
            draft = Annotation(tool: tool, a: point, b: point, points: [point], color: color, width: strokeWidth)
        default:
            draft = Annotation(tool: tool, a: point, b: point, color: color, width: strokeWidth)
        }
        needsDisplay = true
    }

    private func mouseDownSelecting(at point: CGPoint, event: NSEvent) {
        if let index = selectedIndex, let handle = handle(at: point, of: document.annotations[index]) {
            dragHandle = handle
            dragLast = point
            return
        }
        let hit = document.annotations.last { $0.hitTest(point) }
        selectedID = hit?.id
        dragLast = hit == nil ? nil : point
        if let hit, hit.tool == .text, event.clickCount == 2 {
            dragLast = nil
            beginText(at: hit.a, editing: hit)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = documentPoint(event)
        if tool == .select {
            guard let last = dragLast, let index = selectedIndex else { return }
            if !dragMoved {
                dragMoved = true
                checkpoint()
            }
            if dragHandle == \Annotation.a {
                document.annotations[index].a = point
            } else if dragHandle == \Annotation.b {
                document.annotations[index].b = point
            } else {
                document.annotations[index].move(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
            }
            dragLast = point
        } else if tool == .crop {
            cropDraft?.current = point
        } else if var item = draft {
            if tool == .pen || tool == .highlighter {
                item.points.append(point)
            } else {
                item.b = constrained(point, from: item.a, tool: tool, event: event)
            }
            draft = item
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragLast = nil
        dragHandle = nil
        if let item = draft {
            draft = nil
            let visible = item.points.count > 1 || hypot(item.a.x - item.b.x, item.a.y - item.b.y) > 3
            if visible {
                checkpoint()
                document.annotations.append(item)
            }
        }
        if let crop = cropDraft {
            cropDraft = nil
            finishCrop(from: crop.start, to: crop.current)
        }
        needsDisplay = true
    }

    private func finishCrop(from start: CGPoint, to end: CGPoint) {
        let full = document.crop ?? CGRect(origin: .zero, size: renderer.size)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(start.x - end.x), height: abs(start.y - end.y))
            .intersection(full).integral
        guard rect.width >= 8, rect.height >= 8 else { return }
        checkpoint()
        document.crop = rect
        resizeToCrop()
        tool = .select
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select ? .arrow : tool == .text ? .iBeam : .crosshair)
    }

    // MARK: Text

    private func beginText(at point: CGPoint, editing existing: Annotation?) {
        let style = existing ?? Annotation(tool: .text, a: point, b: point, color: color, width: strokeWidth)
        let field = NSTextField(string: existing?.text ?? "")
        field.font = style.font
        field.textColor = style.color
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = "Text"
        field.frame = NSRect(x: point.x - origin.x, y: point.y - origin.y,
                             width: max(240, bounds.width - point.x + origin.x), height: style.font.pointSize * 1.4)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        editingTextID = existing?.id
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitText()
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        let point = CGPoint(x: field.frame.minX + origin.x, y: field.frame.minY + origin.y)
        let font = field.font ?? .systemFont(ofSize: 24)
        let fieldColor = field.textColor ?? color
        field.removeFromSuperview()
        window?.makeFirstResponder(self)

        let index = document.annotations.firstIndex { $0.id == editingTextID }
        editingTextID = nil
        if let index {
            checkpoint()
            if text.isEmpty {
                document.annotations.remove(at: index)
            } else {
                document.annotations[index].text = text
            }
        } else if !text.isEmpty {
            checkpoint()
            var item = Annotation(tool: .text, a: point, b: point, color: fieldColor, width: (font.pointSize - 12) / 3)
            item.text = text
            document.annotations.append(item)
        }
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {        // Delete, Forward Delete
            deleteSelection()
        } else if event.keyCode == 53 {                         // Esc
            if selectedID != nil { selectedID = nil; needsDisplay = true } else { tool = .select }
        } else if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .control, .option]),
                  let key = event.charactersIgnoringModifiers?.lowercased().first,
                  let match = Tool.allCases.first(where: { $0.key == key }) {
            tool = match
        } else {
            super.keyDown(with: event)
        }
    }

    private func deleteSelection() {
        guard let index = selectedIndex else { return }
        checkpoint()
        document.annotations.remove(at: index)
        selectedID = nil
        needsDisplay = true
    }

    private func restyleSelection() {
        guard let index = selectedIndex else { return }
        checkpoint()
        document.annotations[index].color = color
        document.annotations[index].width = strokeWidth
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var items = document.annotations
        if let draft { items.append(draft) }
        renderer.render(items, crop: document.crop, in: ctx)

        ctx.translateBy(x: -origin.x, y: -origin.y)
        if let crop = cropDraft {
            let rect = CGRect(x: min(crop.start.x, crop.current.x), y: min(crop.start.y, crop.current.y),
                              width: abs(crop.start.x - crop.current.x), height: abs(crop.start.y - crop.current.y))
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.addRect(CGRect(origin: origin, size: bounds.size))
            ctx.addRect(rect)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect)
        }
        if let index = selectedIndex {
            drawSelection(of: document.annotations[index], in: ctx)
        }
    }

    private func drawSelection(of item: Annotation, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(item.bounds)
        ctx.setLineDash(phase: 0, lengths: [])
        guard item.tool.usesTwoPoints else { return }
        ctx.setFillColor(NSColor.white.cgColor)
        for point in [item.a, item.b] {
            let dot = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            ctx.fillEllipse(in: dot)
            ctx.strokeEllipse(in: dot)
        }
    }
}
