import AppKit

/// `Qwikshot --readme-art folder` draws the README's example images: a mock
/// window, marked up by the same renderer the editor uses.
enum ReadmeArt {
    private static let size = CGSize(width: 900, height: 560)
    private static let scale: CGFloat = 2

    static func generate(folder: URL) -> Bool {
        guard let scene = makeScene() else { return false }
        let renderer = Renderer(base: scene, scale: scale)

        func item(_ tool: Tool, _ a: CGPoint, _ b: CGPoint, _ color: NSColor = .systemRed) -> Annotation {
            Annotation(tool: tool, a: a, b: b, color: color, width: 4)
        }
        var note = item(.text, CGPoint(x: 452, y: 386), CGPoint(x: 452, y: 386))
        note.text = "Best month so far"
        var first = item(.step, CGPoint(x: 666, y: 130), CGPoint(x: 666, y: 130), .systemBlue)
        first.number = 1
        var second = item(.step, CGPoint(x: 286, y: 474), CGPoint(x: 286, y: 474), .systemBlue)
        second.number = 2
        let arrow = item(.arrow, CGPoint(x: 590, y: 384), CGPoint(x: 662, y: 300))

        let annotated = [
            item(.rectangle, CGPoint(x: 666, y: 130), CGPoint(x: 734, y: 358)),
            arrow, note, first, second,
            item(.pixelate, CGPoint(x: 310, y: 456), CGPoint(x: 590, y: 492)),
        ]
        let focused = [item(.focus, CGPoint(x: 268, y: 116), CGPoint(x: 852, y: 372)), arrow, note]

        guard let markup = renderer.flatten(annotated, crop: nil),
              let focus = renderer.flatten(focused, crop: nil) else { return false }
        return Store.write(markup, scale: scale, to: folder.appendingPathComponent("annotate.png"), type: .png)
            && Store.write(focus, scale: scale, to: folder.appendingPathComponent("focus.png"), type: .png)
    }

    private static func makeScene() -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        drawScene()
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private static func rounded(_ rect: CGRect, _ radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private static func text(_ string: String, _ point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
                             color: NSColor = .labelColor.usingColorSpace(.sRGB) ?? .black) {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]).draw(at: point)
    }

    private static func drawScene() {
        let gray = NSColor(srgbRed: 0.45, green: 0.47, blue: 0.52, alpha: 1)
        let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1)
        let canvas = CGRect(origin: .zero, size: size)
        NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.55, blue: 0.97, alpha: 1),
                            NSColor(srgbRed: 0.56, green: 0.36, blue: 0.90, alpha: 1)])?.draw(in: canvas, angle: 60)

        let window = canvas.insetBy(dx: 28, dy: 28)
        rounded(window, 16, .white)
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            rounded(CGRect(x: 46 + CGFloat(index) * 20, y: 44, width: 12, height: 12), 6, color)
        }

        rounded(CGRect(x: 44, y: 76, width: 196, height: 456), 12, NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        text("Dashboard", CGPoint(x: 60, y: 92), size: 15, weight: .semibold, color: ink)
        for (index, title) in ["Overview", "Revenue", "Customers", "Reports", "Settings"].enumerated() {
            text(title, CGPoint(x: 60, y: 130 + CGFloat(index) * 32), size: 14, color: gray)
        }

        text("Monthly revenue", CGPoint(x: 280, y: 74), size: 26, weight: .bold, color: ink)
        let heights: [CGFloat] = [76, 104, 92, 136, 118, 204, 150]
        for (index, height) in heights.enumerated() {
            let x = 288 + CGFloat(index) * 78
            let color = index == 5 ? NSColor.systemBlue : NSColor(srgbRed: 0.78, green: 0.84, blue: 0.96, alpha: 1)
            rounded(CGRect(x: x, y: 346 - height, width: 44, height: height), 7, color)
        }

        text("Latest customer", CGPoint(x: 280, y: 430), size: 14, weight: .semibold, color: ink)
        text("jordan.taylor@example.com", CGPoint(x: 316, y: 461), size: 21, weight: .semibold, color: ink)
    }
}
