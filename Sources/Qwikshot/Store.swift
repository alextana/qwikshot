import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A capture: its pixels, its backing scale, and its PNG in the history folder.
final class Shot {
    let image: CGImage
    let scale: CGFloat
    let url: URL

    init(image: CGImage, scale: CGFloat, url: URL) {
        self.image = image
        self.scale = scale
        self.url = url
    }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale,
                                             height: CGFloat(image.height) / scale))
    }
}

enum Store {
    private static let historyLimit = 30

    static var historyFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Qwikshot/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func timestampedName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Qwikshot \(formatter.string(from: Date())).\(ext)"
    }

    static func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return url
    }

    static func recordInHistory(image: CGImage, scale: CGFloat) -> Shot? {
        let url = uniqueURL(in: historyFolder, name: timestampedName(ext: "png"))
        guard write(image, scale: scale, to: url, type: .png) else { return nil }
        pruneHistory()
        return Shot(image: image, scale: scale, url: url)
    }

    /// Embeds the DPI so a Retina capture opens at its on-screen size.
    @discardableResult
    static func write(_ image: CGImage, scale: CGFloat, to url: URL, type: UTType) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        let dpi = 72 * scale
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    @discardableResult
    static func saveToFolder(_ image: CGImage, scale: CGFloat) -> URL? {
        let url = uniqueURL(in: Prefs.saveFolder, name: timestampedName(ext: "png"))
        return write(image, scale: scale, to: url, type: .png) ? url : nil
    }

    static func copy(_ image: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    static func recent(limit: Int = 10) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: historyFolder, includingPropertiesForKeys: keys)) ?? []
        func created(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        return Array(files.filter { $0.pathExtension == "png" }.sorted { created($0) > created($1) }.prefix(limit))
    }

    static func load(_ url: URL) -> Shot? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? CGFloat ?? 72
        return Shot(image: image, scale: max(1, dpi / 72), url: url)
    }

    private static func pruneHistory() {
        for url in recent(limit: .max).dropFirst(historyLimit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

enum Prefs {
    private enum Key {
        static let saveFolder = "saveFolder"
    }

    static let copyAfterCapture = "copyAfterCapture"
    static let saveAfterCapture = "saveAfterCapture"
    static let showPreview = "showPreview"
    static let playSound = "playSound"
    static let previewSeconds = "previewSeconds"
    static let recordClicks = "recordClicks"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            copyAfterCapture: true,
            saveAfterCapture: false,
            showPreview: true,
            playSound: true,
            previewSeconds: 6.0,
            recordClicks: true,
        ])
    }

    static func flag(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static var saveFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: Key.saveFolder) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { UserDefaults.standard.set(newValue.path, forKey: Key.saveFolder) }
    }
}
