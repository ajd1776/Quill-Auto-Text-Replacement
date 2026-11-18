import CoreGraphics

/// Virtual key codes used by the expansion engine (ANSI layout positions).
enum KeyCode {
    static let returnKey: Int64 = 36
    static let tab: Int64 = 48
    static let delete: Int64 = 51
    static let escape: Int64 = 53
    static let enter: Int64 = 76
    static let v: CGKeyCode = 9
    static let home: Int64 = 115
    static let pageUp: Int64 = 116
    static let forwardDelete: Int64 = 117
    static let end: Int64 = 119
    static let pageDown: Int64 = 121
    static let leftArrow: Int64 = 123
    static let rightArrow: Int64 = 124
    static let downArrow: Int64 = 125
    static let upArrow: Int64 = 126

    /// Keys that move the insertion point, so whatever was typed before no longer sits behind it.
    static let navigation: Set<Int64> = [
        escape, home, pageUp, forwardDelete, end, pageDown,
        leftArrow, rightArrow, downArrow, upArrow,
    ]
}

extension CGEvent {
    /// The characters this key event would type, if any.
    var typedCharacters: String? {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 32)
        keyboardGetUnicodeString(maxStringLength: 32, actualStringLength: &length, unicodeString: &characters)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
