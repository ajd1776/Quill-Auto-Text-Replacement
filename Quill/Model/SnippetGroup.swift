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

    enum CodingKeys: String, CodingKey {
        case id, name, color, symbol, isEnabled, isExpanded, packID
    }
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

/// The SF Symbols offered for groups and snippets.
enum SnippetSymbols {
    static let all: [(name: String, title: String)] = [
        ("folder.fill", "Folder"),
        ("person.fill", "Person"),
        ("envelope.fill", "Email"),
        ("phone.fill", "Phone"),
        ("house.fill", "Home"),
        ("briefcase.fill", "Work"),
        ("cart.fill", "Shopping"),
        ("bag.fill", "Store"),
        ("shippingbox.fill", "Shipping"),
        ("tag.fill", "Tag"),
        ("link", "Link"),
        ("signature", "Signature"),
        ("text.quote", "Quote"),
        ("bubble.left.fill", "Message"),
        ("calendar", "Calendar"),
        ("creditcard.fill", "Payment"),
        ("mappin.and.ellipse", "Address"),
        ("chevron.left.forwardslash.chevron.right", "Code"),
        ("star.fill", "Star"),
        ("heart.fill", "Heart"),
        ("bolt.fill", "Bolt"),
        ("sparkles", "Sparkles"),
    ]
}
