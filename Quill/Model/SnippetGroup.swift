import SwiftUI

/// A folder of snippets in the sidebar. Turning a group off turns off every snippet in it.
struct SnippetGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: GroupColor = .blue
    var symbol: String = "folder.fill"
    var isEnabled = true
    var isExpanded = true
    /// Set for groups added from a built-in pack, so the pack can be recognised and removed.
    var packID: String?
    /// A colour of the person's own choosing, as #RRGGBB. Overrides `color` when set.
    var customColor: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color, symbol, isEnabled, isExpanded, packID, customColor
    }

    /// The colour to draw this group in.
    var tint: Color {
        customColor.flatMap(Color.init(hex:)) ?? color.color
    }
}

extension Color {
    /// From "#RRGGBB" (or "RRGGBB").
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// "#RRGGBB" in sRGB, for saving.
    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }
}

/// A colour as Quill stores it: one of the system colours by name, or #RRGGBB.
enum QuillColor {
    static func resolve(_ value: String?) -> Color? {
        guard let value else { return nil }
        if let system = GroupColor(rawValue: value) { return system.color }
        return Color(hex: value)
    }
}

extension SnippetGroup {
    /// The group's colour in Quill's stored form: a system colour name, or the custom #RRGGBB.
    var colorValue: String { customColor ?? color.rawValue }
}

/// An icon is either an SF Symbol name or a single emoji.
enum IconKind {
    static func isEmoji(_ icon: String) -> Bool {
        guard icon.count == 1, let scalar = icon.unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || icon.unicodeScalars.count > 1)
    }
}

extension SnippetGroup {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Group"
        color = try container.decodeIfPresent(GroupColor.self, forKey: .color) ?? .blue
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "folder.fill"
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        packID = try container.decodeIfPresent(String.self, forKey: .packID)
        customColor = try container.decodeIfPresent(String.self, forKey: .customColor)
    }
}

/// System colours only, so groups adapt to light, dark and Increase Contrast.
enum GroupColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

