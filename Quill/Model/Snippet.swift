import Foundation

/// When a snippet replaces its shortcut.
enum ExpansionMode: String, Codable, CaseIterable, Identifiable {
    /// After the shortcut is followed by a space, Return, Tab or punctuation.
    case afterDelimiter
    /// As soon as the last character of the shortcut is typed.
    case immediate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .afterDelimiter: "After Space or Punctuation"
        case .immediate: "Immediately"
        }
    }

    var shortTitle: String {
        switch self {
        case .afterDelimiter: "After Space"
        case .immediate: "Immediately"
        }
    }

    var explanation: String {
        switch self {
        case .afterDelimiter: "Type the shortcut, then a space, Return or punctuation."
        case .immediate: "Expands as soon as the last character is typed."
        }
    }
}

/// How the replacement looks when it lands. Everything except Typewriter is drawn
/// as an overlay at the cursor, because Quill can't restyle text inside other apps.
enum ReplacementAnimation: String, Codable, CaseIterable, Identifiable {
    case instant
    case typewriter
    case popBadge
    case glow
    case inkUnderline
    case fadeIn
    case slideIn
    case bounceIn
    case sparkle
    case confetti
    case ripple
    case particleCloud
    case cyber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instant: "None"
        case .typewriter: "Typewriter"
        case .popBadge: "Pop Badge"
        case .glow: "Highlight"
        case .inkUnderline: "Ink Underline"
        case .fadeIn: "Fade In"
        case .slideIn: "Slide In"
        case .bounceIn: "Bounce In"
        case .sparkle: "Sparkle"
        case .confetti: "Confetti"
        case .ripple: "Ripple"
        case .particleCloud: "Particle Cloud"
        case .cyber: "Cyber"
        }
    }

    var symbol: String {
        switch self {
        case .instant: "circle.slash"
        case .typewriter: "character.cursor.ibeam"
        case .popBadge: "capsule.fill"
        case .glow: "highlighter"
        case .inkUnderline: "underline"
        case .fadeIn: "circle.lefthalf.filled"
        case .slideIn: "arrow.right.to.line"
        case .bounceIn: "arrow.down.to.line"
        case .sparkle: "sparkles"
        case .confetti: "party.popper.fill"
        case .ripple: "dot.radiowaves.left.and.right"
        case .particleCloud: "aqi.medium"
        case .cyber: "cpu"
        }
    }

    var explanation: String {
        switch self {
        case .instant: "The text appears instantly, with no effect."
        case .typewriter: "The text types itself out, letter by letter."
        case .popBadge: "A small badge above the text shows which shortcut expanded."
        case .glow: "A tinted highlight appears over the new text, then fades."
        case .inkUnderline: "A brush-stroke underline draws itself under the new text."
        case .fadeIn: "A glass copy of the text fades in over it, then melts away."
        case .slideIn: "A glass copy of the text slides into place, then melts away."
        case .bounceIn: "A glass copy of the text drops in with a bounce, then melts away."
        case .sparkle: "A quick burst of sparkles at the cursor."
        case .confetti: "A small confetti pop at the cursor."
        case .ripple: "Rings ripple out from the cursor, like a drop in water."
        case .particleCloud: "A soft cloud of particles drifts up off the new text."
        case .cyber: "Scrambled characters decode into your text in a neon capsule."
        }
    }

    /// Styles that still play, toned down to a fade, when Reduce Motion is on.
    var survivesReduceMotion: Bool {
        switch self {
        case .instant, .popBadge, .glow, .fadeIn: true
        default: false
        }
    }
}

enum SnippetSortOrder: String, CaseIterable, Identifiable {
    case shortcut
    case mostUsed
    case recentlyUsed
    case newest
    /// The order you arrange by dragging.
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcut: "Shortcut"
        case .mostUsed: "Most Used"
        case .recentlyUsed: "Recently Used"
        case .newest: "Newest"
        case .manual: "Manual"
        }
    }

    /// Sorts snippets in this order. Manual keeps them as arranged in the library.
    func sorted(_ snippets: [Snippet]) -> [Snippet] {
        self == .manual ? snippets : snippets.sorted(by: areInIncreasingOrder)
    }

    func areInIncreasingOrder(_ lhs: Snippet, _ rhs: Snippet) -> Bool {
        if self == .manual { return false }
        // Unnamed snippets stay on top so a new one is easy to find.
        if lhs.trigger.isEmpty != rhs.trigger.isEmpty { return lhs.trigger.isEmpty }
        let byTrigger = lhs.trigger.localizedStandardCompare(rhs.trigger) == .orderedAscending
        switch self {
        case .shortcut:
            return byTrigger
        case .mostUsed:
            return lhs.useCount != rhs.useCount ? lhs.useCount > rhs.useCount : byTrigger
        case .recentlyUsed:
            let left = lhs.lastUsed ?? .distantPast
            let right = rhs.lastUsed ?? .distantPast
            return left != right ? left > right : byTrigger
        case .newest:
            return lhs.created > rhs.created
        case .manual:
            return false
        }
    }
}

struct Snippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
    var mode: ExpansionMode = .afterDelimiter
    var isEnabled = true
    var created = Date()
    /// nil uses the default style from Settings.
    var animation: ReplacementAnimation?
    var useCount = 0
    var lastUsed: Date?
    var groupID: SnippetGroup.ID?
    /// nil uses the group's symbol.
    var symbol: String?
    /// Apps this snippet works in, by bundle identifier. Empty means every app.
    var appBundleIDs: [String] = []
    /// Also expand when the shortcut is typed in other capitals, adapting the text to match.
    var matchesAnyCase = false
    /// The icon's colour: a system colour name or #RRGGBB. nil uses the group's colour.
    var color: String?

    enum CodingKeys: String, CodingKey {
        case id, trigger, expansion, mode, isEnabled, created, animation, useCount, lastUsed, groupID, symbol
        case appBundleIDs, matchesAnyCase, color
    }

    /// Whether this snippet may expand in the app with this bundle identifier.
    func isAllowed(in bundleID: String?) -> Bool {
        guard !appBundleIDs.isEmpty else { return true }
        guard let bundleID else { return false }
        return appBundleIDs.contains(bundleID)
    }

    /// A shortcut the engine can match: not empty and no whitespace.
    var hasValidTrigger: Bool {
        !trigger.isEmpty && !trigger.contains(where: \.isWhitespace)
    }

    /// Keystrokes saved across every use, compared with typing the text out.
    var keysSaved: Int {
        max(0, expansion.count - trigger.count) * useCount
    }

    var preview: String {
        let flat = expansion.replacingOccurrences(of: "\n", with: " ")
        return flat.isEmpty ? "No text" : flat
    }
}

extension Snippet {
    /// Decodes leniently so files saved by earlier versions of Quill still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        expansion = try container.decodeIfPresent(String.self, forKey: .expansion) ?? ""
        mode = try container.decodeIfPresent(ExpansionMode.self, forKey: .mode) ?? .afterDelimiter
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        animation = try? container.decodeIfPresent(ReplacementAnimation.self, forKey: .animation)
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        appBundleIDs = try container.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
        matchesAnyCase = try container.decodeIfPresent(Bool.self, forKey: .matchesAnyCase) ?? false
        color = try container.decodeIfPresent(String.self, forKey: .color)
    }
}

/// Adapts an expansion's capitals to how the shortcut was typed, for snippets that match any case.
enum CaseAdapter {
    static func adapt(_ text: String, typed: String, trigger: String) -> String {
        guard typed != trigger else { return text }
        let letters = typed.filter(\.isLetter)
        guard !letters.isEmpty else { return text }
        // EAD → ALL CAPS
        if letters.count > 1, letters.allSatisfy(\.isUppercase) { return text.uppercased() }
        // Ead → Capitalised first letter
        if let first = letters.first, first.isUppercase, letters.dropFirst().allSatisfy(\.isLowercase) {
            return text.prefix(1).uppercased() + text.dropFirst()
        }
        return text
    }
}
