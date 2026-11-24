#if DEBUG
import AppKit
import CoreGraphics

/// Drives the expansion engine with simulated keystrokes and checks the resulting text.
/// Run with: Quill.app/Contents/MacOS/Quill -QuillSelfTest
@MainActor
enum EngineSelfTest {
    /// A stand-in for the text field in another app, with a movable cursor.
    private struct Document {
        var characters: [Character] = []
        var cursor = 0
        var text: String { String(characters) }

        mutating func apply(_ event: CGEvent) {
            guard event.type == .keyDown else { return }
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case KeyCode.delete:
                if cursor > 0 {
                    characters.remove(at: cursor - 1)
                    cursor -= 1
                }
            case KeyCode.returnKey, KeyCode.enter:
                insert("\n")
            case KeyCode.tab:
                insert("\t")
            case KeyCode.leftArrow:
                cursor = max(0, cursor - 1)
            case KeyCode.rightArrow:
                cursor = min(characters.count, cursor + 1)
            case KeyCode.escape, KeyCode.upArrow, KeyCode.downArrow:
                break
            default:
                if let typed = event.typedCharacters { insert(typed) }
            }
        }

        private mutating func insert(_ string: String) {
            for character in string {
                characters.insert(character, at: cursor)
                cursor += 1
            }
        }
    }

    private static func snippet(_ trigger: String, _ expansion: String, mode: ExpansionMode = .afterDelimiter, enabled: Bool = true) -> Snippet {
        var snippet = Snippet(trigger: trigger, expansion: expansion)
        snippet.mode = mode
        snippet.isEnabled = enabled
        return snippet
    }

    static func run() -> Bool {
        let today = Date().formatted(date: .long, time: .omitted)
        struct Case {
            let name: String
            let keys: String
            let expected: String
            var style: ReplacementAnimation = .instant
            var paused = false
            var bubbleVisible = true
            var frontmost: String? = nil
            var cancelsFillIn = false
            var keepsSpace = true
        }
        let tuples: [(name: String, keys: String, expected: String, style: ReplacementAnimation, paused: Bool)] = [
            ("expands after space", "Email eml ", "Email user@example.com ", .instant, false),
            ("expands after punctuation", "eml.", "user@example.com.", .instant, false),
            ("expands after Return", "eml⏎", "user@example.com\n", .instant, false),
            ("never fires mid-word", "reademl ", "reademl ", .instant, false),
            ("capitals must match", "EML Eml ", "EML Eml ", .instant, false),
            ("Delete undoes straight after", "eml ⌫", "eml", .instant, false),
            ("restored shortcut doesn't re-expand", "eml ⌫ ", "eml ", .instant, false),
            ("Delete after Return just deletes", "eml⏎⌫", "user@example.com", .instant, false),
            ("second Delete is ordinary", "eml ⌫⌫", "em", .instant, false),
            ("typing fixes count", "emX⌫l ", "user@example.com ", .instant, false),
            ("immediate snippet, multi-line", "Hi ;sig", "Hi Best,\nAlex", .instant, false),
            ("disabled snippet ignored", "off ", "off ", .instant, false),
            ("paused does nothing", "eml ", "eml ", .instant, true),
            ("Esc dismisses the bubble", "eml⎋ ", "eml ", .instant, false),
            ("typing on after Esc works again", "eml⎋ eml ", "eml user@example.com ", .instant, false),
            ("Tab accepts a partial match", "em⇥", "user@example.com", .instant, false),
            ("↓ then Tab picks the next suggestion", "em↓⇥", "x@example.com", .instant, false),
            ("exact match first, ↓ to the longer one", "eml↓⇥", "x@example.com", .instant, false),
            ("Delete after Tab restores what was typed", "em⇥⌫", "em", .instant, false),
            ("{date} token", "tdy ", "On \(today) ", .instant, false),
            ("{cursor} places the cursor", "cur x", "Hi x!", .instant, false),
            ("typewriter finishes when you keep typing", "eml x", "user@example.com x", .typewriter, false),
            ("typewriter then Delete undoes", "eml ⌫", "eml", .typewriter, false),
            ("typewriter with {cursor}", "cur x", "Hi x!", .typewriter, false),
        ] + ReplacementAnimation.allCases.filter { $0 != .instant && $0 != .typewriter }.map {
            ("\($0.title) still replaces text", "eml ", "user@example.com ", $0, false)
        }
        let cases = tuples.map { Case(name: $0.name, keys: $0.keys, expected: $0.expected, style: $0.style, paused: $0.paused) } + [
            Case(name: "hidden bubble: Esc passes through to the app", keys: "em⎋l ", expected: "eml ", bubbleVisible: false),
            Case(name: "hidden bubble: Tab is ordinary", keys: "em⇥", expected: "em\t", bubbleVisible: false),
            Case(name: "hidden bubble: ↓ is ordinary, Space still expands", keys: "x eml↓ eml ", expected: "x eml user@example.com ", bubbleVisible: false),
            Case(name: "snippet with no text is skipped", keys: "emp ", expected: "emp "),
            Case(name: "a partial match alone types normally", keys: "em", expected: "em"),
            Case(name: "any-case snippet: lower case", keys: "omw ", expected: "on my way "),
            Case(name: "any-case snippet: ALL CAPS adapts", keys: "OMW ", expected: "ON MY WAY "),
            Case(name: "any-case snippet: Capitalised adapts", keys: "Omw ", expected: "On my way "),
            Case(name: "exact-case snippet ignores other capitals", keys: "EML ", expected: "EML "),
            Case(name: "any-case undo restores what was typed", keys: "OMW ⌫", expected: "OMW"),
            Case(name: "app-limited snippet stays off elsewhere", keys: "shp ", expected: "shp ", frontmost: "com.apple.Safari"),
            Case(name: "app-limited snippet works in its app", keys: "shp ", expected: "Thanks for your order! ", frontmost: "com.apple.mail"),
            Case(name: "fill-in field uses the typed value", keys: "hin ", expected: "Hi AJ, order 42!"),
            Case(name: "cancelling a fill-in puts the shortcut back", keys: "hin ", expected: "hin", cancelsFillIn: true),
            Case(name: "fill-in via Tab from a partial match", keys: "hi⇥", expected: "Hi AJ, order 42!"),
            Case(name: "emoji shortcode expands on the closing colon", keys: "nice :fire:", expected: "nice 🔥"),
            Case(name: "typo fix matches any capitals", keys: "Teh cat", expected: "The cat"),
            Case(name: "no space after: the trigger space is dropped", keys: "Email eml ", expected: "Email user@example.com", keepsSpace: false),
            Case(name: "no space after: typing carries on straight after", keys: "eml x", expected: "user@example.comx", keepsSpace: false),
            Case(name: "no space after: punctuation still goes through", keys: "eml.", expected: "user@example.com.", keepsSpace: false),
            Case(name: "no space after: Return still goes through", keys: "eml⏎", expected: "user@example.com\n", keepsSpace: false),
            Case(name: "no space after: Delete still undoes", keys: "eml ⌫", expected: "eml", keepsSpace: false),
        ]

        let engine = ExpansionEngine.shared
        let saved = (engine.onExpanded, engine.onUndone, engine.styleResolver, engine.onSuggestionsChanged, engine.honoursReduceMotion)
        let savedNeedsInput = engine.onNeedsInput
        engine.onExpanded = nil
        engine.onUndone = nil
        engine.onSuggestionsChanged = nil
        engine.isSelfTesting = true
        // Exercise the real typewriter path even if Reduce Motion is on.
        engine.honoursReduceMotion = false
        engine.suggestionsEnabled = true
        engine.partialSuggestionsEnabled = true
        engine.update(snippets: [
            snippet("eml", "user@example.com"),
            snippet("emlX", "x@example.com"),
            snippet(";sig", "Best,\nAlex", mode: .immediate),
            snippet("off", "SHOULD NOT APPEAR", enabled: false),
            snippet("tdy", "On {date}"),
            snippet("cur", "Hi {cursor}!"),
            snippet("emp", ""),
            { var s = snippet("omw", "on my way"); s.matchesAnyCase = true; return s }(),
            { var s = snippet("shp", "Thanks for your order!"); s.appBundleIDs = ["com.apple.mail"]; return s }(),
            snippet("hin", "Hi {input:Name}, order {input:Order}!"),
            snippet(":fire:", "🔥", mode: .immediate),
            { var s = snippet("teh", "the"); s.matchesAnyCase = true; return s }(),
        ])

        var failures = 0
        for testCase in cases {
            var document = Document()
            KeyboardEmitter.recorder = { document.apply($0) }
            engine.isPaused = testCase.paused
            engine.isBubbleVisible = testCase.bubbleVisible
            engine.keepsTriggerSpace = testCase.keepsSpace
            engine.setFrontmostForTesting(testCase.frontmost)
            let cancels = testCase.cancelsFillIn
            engine.onNeedsInput = { _, fields, completion in
                completion(cancels ? nil : Dictionary(uniqueKeysWithValues: fields.map { ($0, $0 == "Name" ? "AJ" : "42") }))
            }
            engine.styleResolver = { _ in testCase.style }

            for key in testCase.keys {
                let event = keyEvent(for: key)
                if let passed = engine.handle(type: .keyDown, event: event) {
                    document.apply(passed.takeUnretainedValue())
                }
            }
            // A click ends the case, which also flushes any typewriter text still queued.
            if let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left) {
                _ = engine.handle(type: .leftMouseDown, event: click)
            }

            let passed = document.text == testCase.expected
            if !passed { failures += 1 }
            print("\(passed ? "PASS" : "FAIL")  \(testCase.name)"
                  + (passed ? "" : "\n      expected \(testCase.expected.debugDescription)\n      got      \(document.text.debugDescription)"))
        }

        KeyboardEmitter.recorder = nil
        engine.isSelfTesting = false
        engine.keepsTriggerSpace = AppState.shared.addsSpaceAfterSnippet
        engine.isPaused = false
        engine.isBubbleVisible = false
        engine.onNeedsInput = savedNeedsInput
        engine.setFrontmostForTesting(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        (engine.onExpanded, engine.onUndone, engine.styleResolver, engine.onSuggestionsChanged, engine.honoursReduceMotion) = saved
        let modelFailures = runModelChecks()
        let total = cases.count + modelChecks
        print("\(total - failures - modelFailures)/\(total) passed")
        return failures == 0 && modelFailures == 0
    }

    private static let modelChecks = 20

    /// Data checks on in-memory values only; never touches the real snippets file.
    private static func runModelChecks() -> Int {
        var failures = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            let ok = condition()
            if !ok { failures += 1 }
            print("\(ok ? "PASS" : "FAIL")  model: \(name)")
        }

        var group = SnippetGroup(name: "Work")
        group.color = .teal
        var snippet = Snippet(trigger: "sig", expansion: "Best,\nAlex")
        snippet.groupID = group.id
        snippet.useCount = 3
        let library = QuillLibrary(snippets: [snippet], groups: [group], dailyUses: ["2026-11-17": 4])
        let decoded = try? QuillLibrary.decode(library.encoded())
        check("library survives save and load",
              decoded?.snippets.first?.trigger == "sig" && decoded?.groups.first?.color == .teal
                && decoded?.snippets.first?.groupID == group.id && decoded?.dailyUses["2026-11-17"] == 4)

        let legacy = #"[{"id":"\#(UUID().uuidString)","trigger":"eml","expansion":"x@y.z","mode":"afterDelimiter","isEnabled":true,"created":"2026-11-17T10:00:00Z"}]"#
        let legacyLibrary = try? QuillLibrary.decode(Data(legacy.utf8))
        check("Quill 1.0 files still load", legacyLibrary?.snippets.first?.trigger == "eml" && legacyLibrary?.snippets.first?.useCount == 0)

        check("garbage is rejected, not read as empty", (try? QuillLibrary.decode(Data("not json".utf8))) == nil)

        let cursor = TokenRenderer.render("Hi {cursor}, {clipboard}!", clipboard: "AJ")
        check("tokens render and place the cursor", cursor.text == "Hi , AJ!" && cursor.cursorBack == 5)

        let plain = TokenRenderer.render("no tokens {here}")
        check("unknown braces are left alone", plain.text == "no tokens {here}" && plain.cursorBack == nil)

        check("empty expansion is flagged", {
            let empty = Snippet(trigger: "x", expansion: "")
            return empty.preview == "No text"
        }())

        check("fill-in labels found once, in order",
              TokenRenderer.inputFields(in: "{input:Name} {input:Order} {input:Name}") == ["Name", "Order"])
        check("fill-in values render", TokenRenderer.render("Hi {input:Name}!", inputs: ["Name": "AJ"]).text == "Hi AJ!")
        check("case adapter leaves exact typing alone", CaseAdapter.adapt("on my way", typed: "omw", trigger: "omw") == "on my way")

        let year = String(Calendar.current.component(.year, from: Date()))
        check("{date:yyyy} formats", TokenRenderer.render("© {date:yyyy}").text == "© \(year)")
        check("emoji icons are recognised", IconKind.isEmoji("😄") && IconKind.isEmoji("❤️") && IconKind.isEmoji("🇬🇧"))
        check("symbol names aren't emoji", !IconKind.isEmoji("folder.fill") && !IconKind.isEmoji("a") && !IconKind.isEmoji("1"))
        check("starter packs have unique shortcuts", StarterPack.all.allSatisfy { Set($0.entries.map(\.trigger)).count == $0.entries.count })

        check("1.10 is newer than 1.9", UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        check("1.1 equals 1.1.0", !UpdateChecker.isVersion("1.1.0", newerThan: "1.1") && !UpdateChecker.isVersion("1.1", newerThan: "1.1.0"))
        check("older isn't newer", !UpdateChecker.isVersion("1.0", newerThan: "1.1"))
        check("2.0 beats 1.99.9", UpdateChecker.isVersion("2.0", newerThan: "1.99.9"))
        let sample = ###"{"tag_name":"v1.2.0","name":"Quill 1.2","body":"## New","html_url":"https://example.com/r","published_at":"2026-11-20T10:00:00Z","assets":[{"name":"notes.txt","browser_download_url":"https://example.com/n"},{"name":"Quill-1.2.dmg","browser_download_url":"https://example.com/q.dmg"}]}"###
        let parsed = try? UpdateChecker.parse(Data(sample.utf8))
        check("release parses, v stripped, DMG found", parsed?.version == "1.2.0" && parsed?.downloadURL?.absoluteString == "https://example.com/q.dmg")
        check("release without a DMG falls back to its page", (try? UpdateChecker.parse(Data(#"{"tag_name":"1.3","html_url":"https://example.com/p","assets":[]}"#.utf8)))?.downloadURL == nil)

        let sorted = [Snippet(trigger: "b", expansion: "1"), Snippet(trigger: "", expansion: "2"), Snippet(trigger: "a", expansion: "3")]
            .sorted(by: SnippetSortOrder.shortcut.areInIncreasingOrder)
        check("new (unnamed) snippets sort first", sorted.map(\.trigger) == ["", "a", "b"])

        return failures
    }

    /// ⌫ Delete, ⏎ Return, ⇥ Tab, ⎋ Esc, ↑↓ arrows; anything else is typed as that character.
    private static func keyEvent(for key: Character) -> CGEvent {
        let special: [Character: Int64] = [
            "⌫": KeyCode.delete, "⏎": KeyCode.returnKey, "⇥": KeyCode.tab,
            "⎋": KeyCode.escape, "↑": KeyCode.upArrow, "↓": KeyCode.downArrow,
        ]
        let keyCode = special[key].map { CGKeyCode($0) } ?? (key == " " ? 49 : 0)
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = []
        if special[key] == nil {
            let units = Array(String(key).utf16)
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
        }
        return event
    }
}
#endif
