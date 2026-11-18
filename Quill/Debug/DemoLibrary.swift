#if DEBUG
import Foundation

/// Made-up snippets for screenshots (run with -QuillDemoData). Never saved.
@MainActor
enum DemoLibrary {
    static func make() -> QuillLibrary {
        var personal = SnippetGroup(name: "Personal", color: .blue, symbol: "person.fill")
        var shop = SnippetGroup(name: "Shop", color: .orange, symbol: "bag.fill")
        var code = SnippetGroup(name: "Code", color: .purple, symbol: "chevron.left.forwardslash.chevron.right")
        personal.isExpanded = true
        shop.isExpanded = true
        code.isExpanded = true

        func snippet(_ trigger: String, _ text: String, _ group: SnippetGroup?, uses: Int, symbol: String? = nil,
                     mode: ExpansionMode = .afterDelimiter, anyCase: Bool = false) -> Snippet {
            var s = Snippet(trigger: trigger, expansion: text)
            s.groupID = group?.id
            s.useCount = uses
            s.lastUsed = uses > 0 ? Date().addingTimeInterval(-Double(uses) * 900) : nil
            s.symbol = symbol
            s.mode = mode
            s.matchesAnyCase = anyCase
            return s
        }

        let snippets = [
            snippet("eml", "name@example.com", personal, uses: 64, symbol: "envelope.fill"),
            snippet("addr", "1 Example Street\nLondon EC1A 1AA", personal, uses: 21, symbol: "mappin.and.ellipse"),
            snippet("sig", "Best,\nAlex", personal, uses: 38, symbol: "signature"),
            snippet("sigw", "Best regards,\nAlex Smith\nExample Ltd", personal, uses: 12, symbol: "signature"),
            snippet("omw", "on my way", personal, uses: 17, anyCase: true),
            snippet("thx", "Hi {input:Name}, thanks for your order {input:Order}! It ships {date}.", shop, uses: 29, symbol: "shippingbox.fill"),
            snippet("ret", "You can return any item within 30 days. Reply to this email and we'll send a label.", shop, uses: 9),
            snippet(";date", "{date}", nil, uses: 33, symbol: "calendar", mode: .immediate),
            snippet("clog", "console.log({cursor})", code, uses: 14),
            snippet("todo", "// TODO: {cursor}", code, uses: 6),
        ]

        var daily: [String: Int] = [:]
        let pattern = [6, 9, 4, 11, 13, 7, 2, 3, 12, 15, 10, 8, 14, 11]
        for (offset, uses) in pattern.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(13 - offset), to: Date()) ?? Date()
            daily[SnippetStore.dayKey(for: date)] = uses
        }
        return QuillLibrary(snippets: snippets, groups: [personal, shop, code], dailyUses: daily)
    }
}
#endif
