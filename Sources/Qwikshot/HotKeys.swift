import Carbon.HIToolbox

/// The global shortcuts. All of them are Command-Shift plus a number.
enum CaptureShortcut {
    static let modifiers = cmdKey | shiftKey
    static let all = [
        (title: "Capture Area", keys: "⌘⇧4", keyCode: kVK_ANSI_4),
        (title: "Capture Window", keys: "⌘⇧5", keyCode: kVK_ANSI_5),
        (title: "Capture Full Screen", keys: "⌘⇧3", keyCode: kVK_ANSI_3),
        (title: "Capture Text", keys: "⌘⇧7", keyCode: kVK_ANSI_7),
        (title: "Record Screen", keys: "⌘⇧6", keyCode: kVK_ANSI_6),
    ]

    /// The keys on the Screenshots page of Keyboard Shortcuts. macOS also reports ⌘⇧6
    /// and ⌘⇧7 as enabled, but no setting turns those off, so they aren't asked about.
    private static let screenshotKeys = [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]

    /// The keys macOS is keeping for itself. It answers those first, and registering
    /// one here still succeeds, so this is the only way to tell.
    static func heldBySystem() -> [String] {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let list = hotKeys?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return held(by: list)
    }

    static func held(by hotKeys: [[String: Any]]) -> [String] {
        all.filter { shortcut in
            screenshotKeys.contains(shortcut.keyCode) && hotKeys.contains {
                $0[kHISymbolicHotKeyEnabled] as? Bool == true
                    && $0[kHISymbolicHotKeyCode] as? Int == shortcut.keyCode
                    && $0[kHISymbolicHotKeyModifiers] as? Int == modifiers
            }
        }.map(\.keys)
    }
}

/// Global shortcuts via Carbon, which needs no Accessibility permission.
final class HotKeys {
    static let shared = HotKeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5157_494B), id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeys.shared.fire(id.id)
            return noErr
        }, 1, &spec, nil, nil)
    }
}
