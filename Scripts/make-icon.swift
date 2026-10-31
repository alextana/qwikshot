// Draws the app icon. Run from the repo root:
//   swift Scripts/make-icon.swift Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset
import AppKit

func drawIcon() {
    // The macOS icon grid: an 824-point rounded square centred on a 1024-point canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.56, blue: 1, alpha: 1),
                        NSColor(srgbRed: 0.31, green: 0.20, blue: 0.86, alpha: 1)])?.draw(in: shape, angle: -90)

    // A pane of glass: the captured area.
    let pane = NSRect(x: 322, y: 322, width: 380, height: 380)
    let glass = NSBezierPath(roundedRect: pane, xRadius: 56, yRadius: 56)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.62), NSColor.white.withAlphaComponent(0.2)])?.draw(in: glass, angle: -90)
    NSColor.white.withAlphaComponent(0.65).setStroke()
    glass.lineWidth = 5
    glass.stroke()

    // Viewfinder corners.
    NSColor.white.setStroke()
    let inset: CGFloat = 214, reach: CGFloat = 148, radius: CGFloat = 76
    for (sx, sy) in [(CGFloat(-1), CGFloat(1)), (1, 1), (1, -1), (-1, -1)] {
        let cx = 512 + sx * (512 - inset), cy = 512 + sy * (512 - inset)
        let corner = NSBezierPath()
        corner.lineWidth = 44
        corner.lineCapStyle = .round
        corner.move(to: NSPoint(x: cx, y: cy - sy * reach))
        corner.line(to: NSPoint(x: cx, y: cy - sy * radius))
        corner.curve(to: NSPoint(x: cx - sx * radius, y: cy),
                     controlPoint1: NSPoint(x: cx, y: cy - sy * radius * 0.45),
                     controlPoint2: NSPoint(x: cx - sx * radius * 0.45, y: cy))
        corner.line(to: NSPoint(x: cx - sx * reach, y: cy))
        corner.stroke()
    }

    // Light catching the top edge.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
    rim.lineWidth = 4
    NSColor.white.withAlphaComponent(0.35).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let pixels = points * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
    }
}
