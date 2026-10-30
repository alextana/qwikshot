import AppKit
import AVFoundation
import ScreenCaptureKit

/// Records part of a display to an MP4 with ScreenCaptureKit.
@MainActor
final class Recorder: NSObject {
    private(set) var isRecording = false
    var onFinish: ((Result<URL, Error>) -> Void)?

    private var stream: SCStream?
    private var outputDelegate: OutputDelegate?
    private var border: NSWindow?

    /// `rect` is in view coordinates of `shot.screen`: bottom-left origin, points.
    func start(shot: DisplayShot, rect: CGRect) async throws {
        let content = try await Capture.content()
        let scale = shot.screen.backingScaleFactor
        let screenHeight = shot.screen.frame.height

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
        config.width = Int(rect.width * scale) & ~1        // H.264 needs even dimensions
        config.height = Int(rect.height * scale) & ~1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.showMouseClicks = Prefs.flag(Prefs.recordClicks)
        config.queueDepth = 6

        let url = Store.uniqueURL(in: Prefs.saveFolder, name: Store.timestampedName(ext: "mp4"))
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .h264

        let delegate = OutputDelegate(url: url) { [weak self] result in
            Task { @MainActor in self?.finished(result) }
        }
        let stream = SCStream(filter: Capture.recordingFilter(for: shot.display, in: content),
                              configuration: config, delegate: nil)
        let output = SCRecordingOutput(configuration: outputConfig, delegate: delegate)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        outputDelegate = delegate
        isRecording = true
        showBorder(around: rect.offsetBy(dx: shot.screen.frame.minX, dy: shot.screen.frame.minY))
    }

    func stop() {
        guard let stream else { return }
        isRecording = false
        Task { try? await stream.stopCapture() }
    }

    private func finished(_ result: Result<URL, Error>) {
        isRecording = false
        stream = nil
        outputDelegate = nil
        border?.orderOut(nil)
        border = nil
        onFinish?(result)
    }

    /// A click-through outline of the region; the app's own windows are filtered out of the video.
    private func showBorder(around rect: CGRect) {
        let frame = rect.insetBy(dx: -2, dy: -2)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemRed.cgColor
        view.layer?.borderWidth = 2
        window.contentView = view
        window.orderFrontRegardless()
        border = window
    }
}

private final class OutputDelegate: NSObject, SCRecordingOutputDelegate {
    private let url: URL
    private let completion: (Result<URL, Error>) -> Void

    init(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        self.url = url
        self.completion = completion
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        completion(.success(url))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        completion(.failure(error))
    }
}
