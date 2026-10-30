import AppKit
import ImageIO

/// `Qwikshot --render-test out.png` draws every annotation over a synthetic image,
/// so the renderer can be checked without Screen Recording permission.
enum SelfTest {
    static func run(output: URL) -> Bool {
        let scale: CGFloat = 2
        guard let base = makeBase(width: 1600, height: 1000) else { return false }
        let renderer = Renderer(base: base, scale: scale)

        func item(_ tool: Tool, _ a: CGPoint, _ b: CGPoint, _ color: NSColor = .systemRed) -> Annotation {
            Annotation(tool: tool, a: a, b: b, color: color, width: 4)
        }
        var pen = item(.pen, CGPoint(x: 40, y: 300), CGPoint(x: 40, y: 300), .systemBlue)
        pen.points = (0...60).map { CGPoint(x: 40 + CGFloat($0) * 4, y: 300 + sin(CGFloat($0) / 5) * 30) }
        var highlight = item(.highlighter, CGPoint(x: 400, y: 330), CGPoint(x: 400, y: 330), .systemYellow)
        highlight.points = [CGPoint(x: 400, y: 330), CGPoint(x: 740, y: 330)]
        var text = item(.text, CGPoint(x: 400, y: 380), CGPoint(x: 400, y: 380))
        text.text = "Hello Qwikshot"
        var step1 = item(.step, CGPoint(x: 80, y: 420), CGPoint(x: 80, y: 420))
        step1.number = 1
        var step2 = item(.step, CGPoint(x: 140, y: 420), CGPoint(x: 140, y: 420), .systemBlue)
        step2.number = 2
        let annotations = [
            item(.arrow, CGPoint(x: 60, y: 60), CGPoint(x: 300, y: 180)),
            item(.line, CGPoint(x: 340, y: 60), CGPoint(x: 500, y: 180), .systemGreen),
            item(.rectangle, CGPoint(x: 540, y: 60), CGPoint(x: 740, y: 180)),
            pen, highlight, text, step1, step2,
            item(.ellipse, CGPoint(x: 220, y: 380), CGPoint(x: 360, y: 470), .systemOrange),
            item(.pixelate, CGPoint(x: 600, y: 200), CGPoint(x: 760, y: 280)),
        ]

        guard let flat = renderer.flatten(annotations, crop: nil),
              flat.width == base.width, flat.height == base.height,
              let cropped = renderer.flatten(annotations, crop: CGRect(x: 100, y: 50, width: 300, height: 200)),
              cropped.width == 600, cropped.height == 400,
              Store.write(flat, scale: scale, to: output, type: .png),
              let reloaded = Store.load(output), reloaded.scale == scale,
              let recognized = try? OCR.text(in: flat), recognized.contains("Hello Qwikshot") else {
            print("render test FAILED")
            return false
        }
        print("render test passed: \(output.path)")
        return true
    }

    private static func makeBase(width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for x in stride(from: 0, to: width, by: 40) {
            for y in stride(from: 0, to: height, by: 40) {
                let shade = (x + y) / 40 % 2 == 0 ? 0.95 : 0.8
                ctx.setFillColor(CGColor(red: shade, green: shade, blue: CGFloat(x) / CGFloat(width), alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 40, height: 40))
            }
        }
        return ctx.makeImage()
    }
}
