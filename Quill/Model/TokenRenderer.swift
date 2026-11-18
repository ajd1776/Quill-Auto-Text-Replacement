import AppKit

/// Placeholders a snippet can contain, filled in when it expands.
enum SnippetToken: String, CaseIterable, Identifiable {
    case date, time, clipboard, cursor

    var id: String { rawValue }
    var placeholder: String { "{\(rawValue)}" }

    var title: String {
        switch self {
        case .date: "Today's Date"
        case .time: "Current Time"
        case .clipboard: "Clipboard Contents"
        case .cursor: "Cursor Position"
        }
    }

    var symbol: String {
        switch self {
        case .date: "calendar"
        case .time: "clock"
        case .clipboard: "doc.on.clipboard"
        case .cursor: "character.cursor.ibeam"
        }
    }
}

/// Fill-in fields aren't a fixed token: {input:Label} with any label.
enum FillInToken {
    static let title = "Fill-in Field"
    static let symbol = "rectangle.and.pencil.and.ellipsis"
    static func placeholder(_ label: String) -> String { "{input:\(label)}" }
}

/// The text a snippet actually types, with tokens filled in.
struct RenderedText: Equatable {
    var text: String
    /// How many characters the cursor moves back after typing, when the snippet contains {cursor}.
    var cursorBack: Int?
}

enum TokenRenderer {
    /// Every token Quill understands, for highlighting: {date}, {time}, {clipboard}, {cursor} and {input:Label}.
    static let tokenPattern = try! NSRegularExpression(pattern: #"\{(?:date|time|clipboard|cursor|input:[^{}\n]+|date:[^{}\n]+)\}"#)
    /// {date:FORMAT} with a Unicode date pattern, such as {date:dd/MM/yyyy} or {date:EEEE}.
    private static let datePattern = try! NSRegularExpression(pattern: #"\{date:([^{}\n]+)\}"#)
    private static let inputPattern = try! NSRegularExpression(pattern: #"\{input:([^{}\n]+)\}"#)

    static func containsTokens(_ template: String) -> Bool {
        let range = NSRange(template.startIndex..., in: template)
        return tokenPattern.firstMatch(in: template, range: range) != nil
    }

    /// The fill-in field labels in a template, in order, without repeats.
    static func inputFields(in template: String) -> [String] {
        guard template.contains("{input:") else { return [] }
        let range = NSRange(template.startIndex..., in: template)
        var labels: [String] = []
        for match in inputPattern.matches(in: template, range: range) {
            guard let labelRange = Range(match.range(at: 1), in: template) else { continue }
            let label = template[labelRange].trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, !labels.contains(label) { labels.append(label) }
        }
        return labels
    }

    static func render(
        _ template: String,
        inputs: [String: String] = [:],
        now: Date = Date(),
        clipboard: @autoclosure () -> String? = NSPasteboard.general.string(forType: .string)
    ) -> RenderedText {
        guard template.contains("{") else { return RenderedText(text: template) }

        var text = template
        if text.contains("{input:") {
            let range = NSRange(text.startIndex..., in: text)
            var result = ""
            var last = text.startIndex
            for match in inputPattern.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text), let labelRange = Range(match.range(at: 1), in: text) else { continue }
                let label = text[labelRange].trimmingCharacters(in: .whitespaces)
                result += text[last..<whole.lowerBound]
                // Without a value (previews, menus) the label stands in, so the text still reads.
                result += inputs[label] ?? label
                last = whole.upperBound
            }
            result += text[last...]
            text = result
        }
        if text.contains("{date:") {
            let range = NSRange(text.startIndex..., in: text)
            var result = ""
            var last = text.startIndex
            for match in datePattern.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text), let formatRange = Range(match.range(at: 1), in: text) else { continue }
                let formatter = DateFormatter()
                formatter.locale = .current
                formatter.dateFormat = String(text[formatRange])
                result += text[last..<whole.lowerBound] + formatter.string(from: now)
                last = whole.upperBound
            }
            result += text[last...]
            text = result
        }
        text = text.replacingOccurrences(of: SnippetToken.date.placeholder, with: now.formatted(date: .long, time: .omitted))
        text = text.replacingOccurrences(of: SnippetToken.time.placeholder, with: now.formatted(date: .omitted, time: .shortened))
        if text.contains(SnippetToken.clipboard.placeholder) {
            text = text.replacingOccurrences(of: SnippetToken.clipboard.placeholder, with: clipboard() ?? "")
        }

        let cursor = SnippetToken.cursor.placeholder
        guard let range = text.range(of: cursor) else { return RenderedText(text: text) }
        let after = text[range.upperBound...].replacingOccurrences(of: cursor, with: "")
        text = String(text[..<range.lowerBound]) + after
        return RenderedText(text: text, cursorBack: after.count)
    }
}
