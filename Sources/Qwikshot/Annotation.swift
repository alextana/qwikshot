import AppKit
import CoreImage

enum Tool: Int, CaseIterable {
    case select, arrow, line, rectangle, ellipse, pen, highlighter, text, pixelate, focus, step, crop

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pen: "scribble"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .pixelate: "square.grid.3x3.fill"
        case .focus: "viewfinder"
        case .step: "1.circle.fill"
        case .crop: "crop"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .pixelate: "Pixelate"
        case .focus: "Focus"
        case .step: "Numbered Step"
        case .crop: "Crop"
        }
    }

    /// Single-key shortcut, shown in the tool's tooltip.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .pixelate: "b"
        case .focus: "f"
        case .step: "n"
        case .crop: "c"
        }
    }

    var usesTwoPoints: Bool {
        [.arrow, .line, .rectangle, .ellipse, .pixelate, .focus].contains(self)
    }
}

/// All coordinates are in image points with a top-left origin.
struct Annotation {
    let id = UUID()
    var tool: Tool
    var a: CGPoint
    var b: CGPoint
    var points: [CGPoint] = []
    var color: NSColor
    var width: CGFloat
    var text = ""
    var number = 0

    var rect: CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var font: NSFont { .systemFont(ofSize: 12 + width * 3, weight: .semibold) }
    var stepDiameter: CGFloat { 18 + width * 3 }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    var bounds: CGRect {
        switch tool {
        case .pen, .highlighter:
            guard let first = points.first else { return .null }
            return points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
                .insetBy(dx: -width * 2, dy: -width * 2)
        case .text:
            return CGRect(origin: a, size: NSAttributedString(string: text, attributes: textAttributes).size())
        case .step:
            return CGRect(x: a.x - stepDiameter / 2, y: a.y - stepDiameter / 2, width: stepDiameter, height: stepDiameter)
        default:
            return rect.insetBy(dx: -max(width, 6), dy: -max(width, 6))
        }
    }

    mutating func move(by delta: CGVector) {
        a = CGPoint(x: a.x + delta.dx, y: a.y + delta.dy)
        b = CGPoint(x: b.x + delta.dx, y: b.y + delta.dy)
        points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
    }

    func hitTest(_ point: CGPoint) -> Bool {
        let slop: CGFloat = 6
        switch tool {
        case .arrow, .line:
            return Self.distance(from: point, toSegment: a, b) <= max(width, slop)
        case .rectangle, .focus:
            return rect.insetBy(dx: -slop, dy: -slop).contains(point)
                && !rect.insetBy(dx: width + slop, dy: width + slop).contains(point)
        case .pen, .highlighter:
            return zip(points, points.dropFirst()).contains {
                Self.distance(from: point, toSegment: $0, $1) <= max(width, slop)
            }
        default:
            return bounds.contains(point)
        }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Draws a capture and its annotations. The canvas and the exporter share this,
/// so saved output matches the screen. Expects a y-down context measured in image points.
final class Renderer {
    let base: CGImage
    let size: CGSize
    let scale: CGFloat

    /// Filtered once for the whole image: annotations just clip to these.
    private lazy var pixelated: CGImage? = filtered("CIPixellate", [kCIInputScaleKey: 10 * scale])
    private lazy var blurred: CGImage? = filtered("CIGaussianBlur", [kCIInputRadiusKey: 8 * scale])

    init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
        size = CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
    }

    func render(_ annotations: [Annotation], crop: CGRect?, in ctx: CGContext) {
        ctx.saveGState()
        if let crop { ctx.translateBy(x: -crop.minX, y: -crop.minY) }
        drawBackdrop(focusing: annotations.filter { $0.tool == .focus }.map(\.rect), in: ctx)
        for annotation in annotations { draw(annotation, in: ctx) }
        ctx.restoreGState()
    }

    /// The blur belongs to the image, not the annotation stack, so it goes down first:
    /// annotations stay sharp whichever order they were added in.
    private func drawBackdrop(focusing rects: [CGRect], in ctx: CGContext) {
        guard !rects.isEmpty, let blurred else {
            drawImage(base, in: ctx)
            return
        }
        drawImage(blurred, in: ctx)
        for rect in rects {
            ctx.saveGState()
            ctx.clip(to: rect)
            drawImage(base, in: ctx)
            ctx.restoreGState()
        }
    }

    /// Clamped first so edges don't fade, and kept in the source color space
    /// so filtered areas line up with the original pixels around them.
    private func filtered(_ name: String, _ parameters: [String: Any]) -> CGImage? {
        let input = CIImage(cgImage: base)
        guard let filter = CIFilter(name: name, parameters: parameters) else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: base.colorSpace)
    }

    func flatten(_ annotations: [Annotation], crop: CGRect?) -> CGImage? {
        let outputSize = crop?.size ?? size
        let width = Int((outputSize.width * scale).rounded()), height = Int((outputSize.height * scale).rounded())
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        render(annotations, crop: crop, in: ctx)
        return ctx.makeImage()
    }

    private func drawImage(_ image: CGImage, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()
    }

    private func draw(_ item: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = (item.color.usingColorSpace(.sRGB) ?? item.color).cgColor

        if ![.pixelate, .highlighter, .focus].contains(item.tool) {
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                          color: NSColor.black.withAlphaComponent(0.35).cgColor)
        }
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(item.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch item.tool {
        case .select, .crop, .focus:
            break
        case .arrow:
            ctx.addPath(arrowPath(from: item.a, to: item.b, width: item.width))
            ctx.fillPath()
        case .line:
            ctx.strokeLineSegments(between: [item.a, item.b])
        case .rectangle:
            ctx.addPath(CGPath(roundedRect: item.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.strokePath()
        case .ellipse:
            ctx.strokeEllipse(in: item.rect)
        case .pen:
            strokePoints(item.points, in: ctx)
        case .highlighter:
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.45)
            ctx.setLineWidth(item.width * 5)
            ctx.setLineCap(.butt)
            strokePoints(item.points, in: ctx)
        case .pixelate:
            if let pixelated {
                ctx.clip(to: item.rect)
                drawImage(pixelated, in: ctx)
            }
        case .text:
            drawString(NSAttributedString(string: item.text, attributes: item.textAttributes), at: item.a, in: ctx)
        case .step:
            ctx.fillEllipse(in: item.bounds)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            let string = NSAttributedString(string: "\(item.number)", attributes: [
                .font: NSFont.systemFont(ofSize: item.stepDiameter * 0.55, weight: .bold),
                .foregroundColor: NSColor.white,
            ])
            let size = string.size()
            drawString(string, at: CGPoint(x: item.a.x - size.width / 2, y: item.a.y - size.height / 2), in: ctx)
        }
    }

    private func strokePoints(_ points: [CGPoint], in ctx: CGContext) {
        guard points.count > 1 else { return }
        ctx.addLines(between: points)
        ctx.strokePath()
    }

    private func drawString(_ string: NSAttributedString, at point: CGPoint, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        string.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A shaft tapering from the tail up to a solid head.
    private func arrowPath(from a: CGPoint, to b: CGPoint, width: CGFloat) -> CGPath {
        let length = hypot(b.x - a.x, b.y - a.y)
        let path = CGMutablePath()
        guard length > 0 else { return path }
        let headLength = min(10 + width * 3.5, length)
        let headHalf = headLength * 0.5
        let neck = length - headLength * 0.8
        let shaftHalf = width * 0.75
        path.addLines(between: [
            CGPoint(x: 0, y: -0.5), CGPoint(x: neck, y: -shaftHalf),
            CGPoint(x: length - headLength, y: -headHalf), CGPoint(x: length, y: 0),
            CGPoint(x: length - headLength, y: headHalf), CGPoint(x: neck, y: shaftHalf),
            CGPoint(x: 0, y: 0.5),
        ], transform: CGAffineTransform(translationX: a.x, y: a.y)
            .rotated(by: atan2(b.y - a.y, b.x - a.x)))
        path.closeSubpath()
        return path
    }
}
