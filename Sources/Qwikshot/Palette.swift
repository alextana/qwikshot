import AppKit
import SwiftUI

/// The editor's shared state: the SwiftUI palette reads it, and it drives the canvas.
@Observable
final class EditorModel {
    @ObservationIgnored weak var canvas: CanvasView?

    var tool: Tool = .arrow {
        didSet {
            guard let canvas, canvas.tool != tool else { return }
            canvas.tool = tool
            canvas.window?.makeFirstResponder(canvas)
        }
    }
    var color: NSColor = .systemRed {
        didSet { canvas?.color = color }
    }
    var strokeWidth: CGFloat = 4 {
        didSet { canvas?.strokeWidth = strokeWidth }
    }

    @ObservationIgnored private lazy var colorRelay = ColorPanelRelay { [weak self] in self?.color = $0 }

    func pickCustomColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(colorRelay)
        panel.setAction(#selector(ColorPanelRelay.colorChanged))
        panel.orderFront(nil)
    }
}

/// NSColorPanel reports through target-action, which needs an NSObject.
private final class ColorPanelRelay: NSObject {
    private let onChange: (NSColor) -> Void

    init(onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) { onChange(sender.color) }
}

/// Where each tool button sits, so the selection circle can find it.
private struct ToolBoundsKey: PreferenceKey {
    static let defaultValue: [Tool: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Tool: Anchor<CGRect>], nextValue: () -> [Tool: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The floating tool palette: tools on the left, what they draw with on the right.
struct ToolPalette: View {
    @Bindable var model: EditorModel
    @State private var showsWidth = false

    private static let groups: [[Tool]] = [
        [.select], [.arrow, .line, .rectangle, .ellipse], [.pen, .highlighter, .text],
        [.pixelate, .focus], [.step], [.crop],
    ]
    private static let swatches: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]

    private var usesStyle: Bool { ![.crop, .pixelate, .focus].contains(model.tool) }

    private var usesCustomColor: Bool { !Self.swatches.contains(model.color) }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                tools
                style
            }
        }
        .padding(8)
        .animation(Motion.standard, value: model.tool)
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(Self.groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider().frame(height: 18).padding(.horizontal, 4)
                }
                ForEach(Self.groups[index], id: \.self, content: toolButton)
            }
        }
        .backgroundPreferenceValue(ToolBoundsKey.self, selectionIndicator)
        .padding(5)
        .glassEffect(.regular, in: .capsule)
    }

    /// One circle that travels between tools. Giving each tool its own would
    /// fade one out and the next in, because they'd be separate views.
    private func selectionIndicator(_ bounds: [Tool: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let anchor = bounds[model.tool] {
                let rect = proxy[anchor]
                Circle()
                    .fill(.tint)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(Motion.reduced ? nil : Motion.standard, value: model.tool)
            }
        }
    }

    private func toolButton(_ tool: Tool) -> some View {
        let selected = model.tool == tool
        return Button { model.tool = tool } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .anchorPreference(key: ToolBoundsKey.self, value: .bounds) { [tool: $0] }
        .help("\(tool.title) (\(tool.key.uppercased()))")
        .accessibilityLabel(tool.title)
    }

    private var style: some View {
        HStack(spacing: 6) {
            ForEach(Self.swatches, id: \.self, content: swatch)
            customSwatch
            Button { showsWidth.toggle() } label: {
                Image(systemName: "lineweight")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("Stroke and text size")
            .popover(isPresented: $showsWidth, arrowEdge: .top) {
                Slider(value: $model.strokeWidth, in: 1...12) { Text("Size") }
                    .labelsHidden()
                    .frame(width: 170)
                    .padding(14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .disabled(!usesStyle)
        .opacity(usesStyle ? 1 : 0.4)
        .glassEffect(.regular, in: .capsule)
    }

    private var customSwatch: some View {
        Button { model.pickCustomColor() } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay { if usesCustomColor { Circle().strokeBorder(.tint, lineWidth: 2) } }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help("Custom Color")
    }

    private func swatch(_ color: NSColor) -> some View {
        let selected = model.color == color
        return Button { model.color = color } label: {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 18, height: 18)
                .overlay { Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5) }
                .padding(3)
                .overlay { if selected { Circle().strokeBorder(.tint, lineWidth: 2) } }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}
