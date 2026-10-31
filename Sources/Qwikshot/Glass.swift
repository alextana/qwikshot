import AppKit
import SwiftUI

/// Shared motion. Critically damped, because nothing here is thrown by a gesture
/// and overshoot on a panel that simply appears feels wrong.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var standard: Animation {
        reduced ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 1)
    }

    /// How long to keep a panel on screen while its exit plays.
    static let exitDelay: TimeInterval = 0.4
}

/// A transparent, click-through-free panel that never activates the app,
/// so the frontmost app keeps focus while glass floats above it.
class FloatingPanel: NSPanel {
    init(size: NSSize, level: NSWindow.Level = .floating) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
}

/// Hosts SwiftUI in a panel that isn't key: takes the first click, and tracks
/// the pointer even while another app is active.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Draws SwiftUI without taking any mouse events from the view beneath it.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Answers on press, not release.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 1), value: configuration.isPressed)
    }
}
