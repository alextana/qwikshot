import AppKit
import ImageIO

/// `Qwikshot --render-test out.png` draws every annotation over a synthetic image,
/// so the renderer can be checked without Screen Recording permission.
enum SelfTest {
    @MainActor
    static func run(output: URL) -> Bool {
        guard dockFollowsWindows() else {
            print("dock test FAILED")
            return false
        }
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
            item(.focus, CGPoint(x: 40, y: 40), CGPoint(x: 320, y: 200)),
        ]

        // The checker squares meet at multiples of 40 pixels, where a blur changes the most.
        let focusRect = item(.focus, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250))
        func changed(_ image: CGImage, x: Int, y: Int) -> Int {
            abs(Int(pixel(image, x: x, y: y)[1]) - Int(pixel(base, x: x, y: y)[1]))
        }

        guard let focused = renderer.flatten([focusRect], crop: nil),
              changed(focused, x: 398, y: 250) <= 1,            // inside stays sharp
              changed(focused, x: 798, y: 250) > 8,             // right of the rectangle
              changed(focused, x: 398, y: 750) > 8,             // below it, which catches a flipped clip
              let flat = renderer.flatten(annotations, crop: nil),
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

    /// The Dock icon must outlast all but the final window, then go.
    @MainActor
    private static func dockFollowsWindows() -> Bool {
        func makeWindow() -> NSWindow {
            let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            return window
        }
        let first = makeWindow(), second = makeWindow()
        NSApp.setActivationPolicy(.accessory)
        DockPresence.track(first)
        DockPresence.track(second)
        let shownWhileOpen = NSApp.activationPolicy() == .regular
        first.close()
        let keptForLastWindow = NSApp.activationPolicy() == .regular
        second.close()
        return shownWhileOpen && keptForLastWindow && NSApp.activationPolicy() == .accessory
    }

    /// `Qwikshot --ui-snapshots folder` opens the editor, a preview and a toast, then writes
    /// each window's view hierarchy to a PNG. It checks layout without Screen Recording
    /// permission, but real glass only composites on screen.
    @MainActor
    static func snapshotUI(folder: URL) {
        guard let base = makeBase(width: 1600, height: 1000) else { exit(1) }
        let shot = Shot(image: base, scale: 2, url: folder.appendingPathComponent("sample.png"))
        Store.write(base, scale: 2, to: shot.url, type: .png)
        EditorWindowController.open(shot)
        PreviewManager.shared.show(shot)
        Toast.show("Copied", symbol: "doc.on.doc.fill")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = "window-\(index)-\(Int(view.bounds.width))x\(Int(view.bounds.height)).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
            }
            exit(0)
        }
    }

    /// RGBA of the pixel at `x`, `y`, measured from the top left.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
        }
        return bytes
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
