import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, such as ⌃⌥⌘Q.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt
    var keyLabel: String

    /// Builds a hotkey from a key press. Needs at least one of ⌘, ⌃ or ⌥ so it can't steal ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        modifierFlags = flags.rawValue
        keyLabel = Self.label(for: event)
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    /// In Apple's standard order: Control, Option, Shift, Command.
    var displayString: String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func label(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

enum HotkeyAction: UInt32, CaseIterable {
    case toggleQuill = 1
    case searchSnippets = 2
}

/// Registers global hotkeys with the system. Unlike the expansion engine,
/// these work without Accessibility access and while Quill is paused.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var handler: ((HotkeyAction) -> Void)?

    private var references: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), quillHotKeyHandler, 1, &spec, nil, &eventHandler)
    }

    /// Replaces every registered hotkey. Returns the actions whose shortcut is taken by another app.
    @discardableResult
    func register(_ hotkeys: [HotkeyAction: Hotkey]) -> Set<HotkeyAction> {
        unregisterAll()
        var failed = Set<HotkeyAction>()
        for (action, hotkey) in hotkeys {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5155_494C), id: action.rawValue)
            let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                references[action] = reference
            } else {
                failed.insert(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        guard let action = HotkeyAction(rawValue: id) else { return }
        handler?(action)
    }
}

private func quillHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }
    MainActor.assumeIsolated {
        HotKeyCenter.shared.fire(id.id)
    }
    return noErr
}
