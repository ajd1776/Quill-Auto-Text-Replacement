#if DEBUG
import AppKit
import SwiftUI

/// Scripted scenes for the README video and GIFs (run with -QuillDemoData -QuillDemo stage:<scene>).
/// A text window on a plain backdrop is "typed" into on a timer, and the real suggestion bubble,
/// effects, fill-in form, menu bar panel and library window react to it. Nothing here reads or
/// writes the real library, and the recording area holds only Quill's own windows.
@MainActor
final class DemoStage {
    static let shared = DemoStage()

    private var window: NSWindow?
    private var textView: NSTextView?
    private var extraWindow: NSWindow?

    /// The stage size in points. Recorded at 2x.
    nonisolated static let size = CGSize(width: 760, height: 300)

    private var state: AppState { AppState.shared }

    func run(_ scene: String, openLibrary: @escaping () -> Void) {
        // Park the pointer in the bottom-right corner, out of the recorded area.
        if let screen = NSScreen.screens.first?.frame {
            CGWarpMouseCursorPosition(CGPoint(x: screen.maxX - 4, y: screen.maxY - 4))
        }
        NSApp.activate()
        switch scene {
        case "hero": stage { try await self.hero() }
        case "bubble": stage { try await self.bubble() }
        case "fillin": stage(height: 460) { try await self.fillIn() }
        case "effects": stage { try await self.effects() }
        case "panel": panel()
        case "tour": tour(openLibrary: openLibrary)
        default: print("Unknown demo scene \(scene)"); exit(1)
        }
    }

    // MARK: Scenes

    private func hero() async throws {
        try await pause(0.3)
        try await type("I'm ")
        try await typeTrigger("omw", into: "on my way", effect: .popBadge, bubble: true)
        try await type("\n")
        try await chooseFromBubble(typed: "si", choices: ["sig", "sigw"], pick: 1, effect: .sparkle)
        try await pause(1.3)
    }

    private func bubble() async throws {
        try await pause(0.3)
        try await chooseFromBubble(typed: "si", choices: ["sig", "sigw"], pick: 1, effect: .glow)
        try await pause(1.2)
    }

    private func fillIn() async throws {
        try await pause(0.3)
        try await type("thx ", speed: 0.07)
        guard let snippet = snippet("thx") else { return }
        let start = length - 4
        FillInController.demoWithoutFocus = true
        FillInController.demoCaret = caretRect
        var inputs: [String: String] = [:]
        FillInController.shared.present(snippet: snippet, fields: ["Name", "Order"]) { values in
            inputs = values ?? [:]
        }
        try await pause(0.6)
        for (field, value) in [("Name", "Sam"), ("Order", "#1042")] {
            for index in value.indices {
                FillInController.shared.demoModel?.values[field] = String(value[...index])
                try await pause(0.07)
            }
            try await pause(0.25)
        }
        try await pause(0.4)
        FillInController.shared.demoSubmit()
        try await pause(0.2)
        let text = TokenRenderer.render(snippet.expansion, inputs: inputs, clipboard: "").text
        replace(from: start, with: text)
        play(.confetti, trigger: "thx", inserted: text)
        try await pause(1.4)
    }

    private func effects() async throws {
        try await pause(0.3)
        let lines: [(String, String, [ReplacementAnimation])] = [
            ("omw", "on my way", [.cyber]),
            ("eml", "name@example.com", [.confetti]),
            // Two effects combined, as Settings › Effects allows.
            ("omw", "on my way", [.popBadge, .sparkle]),
        ]
        for (index, line) in lines.enumerated() {
            try await typeTrigger(line.0, into: line.1, effect: line.2[0], also: Array(line.2.dropFirst()), bubble: false)
            try await pause(0.7)
            if index < lines.count - 1 { try await type("\n") }
        }
        try await pause(0.6)
    }

    /// The menu bar panel: search, then the group filters.
    private func panel() {
        let screen = NSScreen.main?.frame ?? .zero
        let area = CGRect(x: 120, y: screen.maxY - 110 - 660, width: 600, height: 660)
        let backdrop = makeBackdrop(area)
        let host = NSHostingController(rootView: MenuBarPanel().environment(state).ignoresSafeArea())
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(backdrop.level.rawValue + 1)
        panel.orderFrontRegardless()
        extraWindow = panel

        _ = Task {
            try await pause(0.5)
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + 10))
            report(area)
            @MainActor func send(_ info: [String: String]) { NotificationCenter.default.post(name: .quillDemoPanel, object: nil, userInfo: info) }
            try await pause(0.6)
            for query in ["s", "si", "sig"] {
                send(["query": query])
                try await pause(0.25)
            }
            try await pause(0.9)
            send(["query": ""])
            try await pause(0.4)
            for filter in ["Shop", "all"] {
                send(["filter": filter])
                try await pause(0.9)
            }
            print("QUILL-DEMO-DONE"); fflush(stdout)
        }
    }

    /// The library window: editor with notes, switches, groups, the Edit sheet, then Stats and the Firing Range.
    private func tour(openLibrary: @escaping () -> Void) {
        state.selection = []
        state.selection = []
        openLibrary()
        _ = Task {
            try await pause(1.6)
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains(WindowID.library) == true }) else { return }
            let screen = NSScreen.main?.frame ?? .zero
            let area = CGRect(x: 100, y: screen.maxY - 100 - 800, width: 1320, height: 800)
            let backdrop = self.makeBackdrop(area)
            window.level = NSWindow.Level(backdrop.level.rawValue + 1)
            window.setFrame(area.insetBy(dx: 40, dy: 40), display: true)
            window.orderFrontRegardless()
            try await pause(0.4)
            self.report(area)
            try await pause(0.6)

            @MainActor func select(_ trigger: String) {
                if let id = snippet(trigger)?.id { state.selection = [.snippet(id)] }
            }
            if let id = snippet("eml")?.id { state.store.update(id) { $0.notes = "Work email for forms and sign-ups" } }
            select("eml")
            try await pause(1.2)
            // Switch a snippet off and on again, right in the row.
            if let id = snippet("omw")?.id {
                withAnimation { state.store.setEnabled(id, false) }
                try await pause(0.6)
                withAnimation { state.store.setEnabled(id, true) }
                try await pause(0.4)
            }
            // Collapse and expand a group.
            if let shop = state.store.groups.first(where: { $0.name == "Shop" }) {
                withAnimation(.snappy(duration: 0.2)) { state.store.updateGroup(shop.id) { $0.isExpanded = false } }
                try await pause(0.7)
                withAnimation(.snappy(duration: 0.2)) { state.store.updateGroup(shop.id) { $0.isExpanded = true } }
                try await pause(0.5)
                // The Edit sheet: shortcut, text, notes, group, colour and icon in one place.
                if let thx = snippet("thx")?.id {
                    state.store.update(thx) { $0.notes = "Order confirmation for shop customers" }
                    state.appearanceTarget = .snippet(thx)
                    try await pause(2.0)
                    state.appearanceTarget = nil
                    try await pause(0.5)
                }
            }
            state.page = .stats
            try await pause(1.2)
            state.page = .firingRange
            try await pause(1.2)
            print("QUILL-DEMO-DONE"); fflush(stdout)
        }
    }

    // MARK: Stage

    private func stage(height: CGFloat = DemoStage.size.height, _ script: @escaping @MainActor () async throws -> Void) {
        let screen = NSScreen.main?.frame ?? .zero
        let frame = CGRect(x: 120, y: screen.maxY - 110 - height, width: Self.size.width, height: height)
        let window = StageWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let textView = NSTextView()
        textView.font = .systemFont(ofSize: 19)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.textContainerInset = CGSize(width: 22, height: 18)
        textView.insertionPointColor = .controlAccentColor
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor.labelColor,
                                     .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 5; return p }()]
        window.contentView = NSHostingView(rootView: StageView(textView: textView))
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        window.makeFirstResponder(textView)
        self.window = window
        self.textView = textView
        report(frame)
        _ = Task {
            try await pause(0.5)
            try await script()
            print("QUILL-DEMO-DONE"); fflush(stdout)
        }
    }

    /// An opaque backdrop over the recorded area, so nothing else on screen can show through.
    private var backdrops: [NSWindow] = []

    private func makeBackdrop(_ frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: StageBackdrop())
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        backdrops.append(window)
        return window
    }

    /// Tells the recording script which part of the screen to capture, in top-left screen points.
    private func report(_ frame: CGRect) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        print("QUILL-DEMO-RECT \(Int(frame.minX)),\(Int(height - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))")
        fflush(stdout)
    }

    // MARK: Typing

    private var length: Int { textView?.string.utf16.count ?? 0 }

    private var caretRect: CGRect {
        guard let textView else { return .zero }
        var rect = textView.firstRect(forCharacterRange: NSRange(location: length, length: 0), actualRange: nil)
        if rect.height < 4 { rect.size.height = 22 }
        return rect
    }

    private func type(_ text: String, speed: Double = 0.055) async throws {
        for character in text {
            append(String(character))
            try await pause(character == " " ? speed * 1.6 : character == "\n" ? speed * 3 : speed * Double.random(in: 0.7...1.3))
        }
    }

    private func append(_ text: String) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.append(NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.setSelectedRange(NSRange(location: length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private func replace(from start: Int, with text: String) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.replaceCharacters(in: NSRange(location: start, length: length - start),
                                  with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.setSelectedRange(NSRange(location: length, length: 0))
    }

    /// Types a shortcut and a space, then expands it like the engine does: the shortcut goes, the text arrives.
    /// Types a shortcut and a space, then swaps in the text like the engine: the space stays only
    /// when that setting is on. `also` plays more effects together with the first.
    private func typeTrigger(_ trigger: String, into text: String, effect: ReplacementAnimation,
                             also: [ReplacementAnimation] = [], bubble: Bool) async throws {
        let start = length
        for (index, character) in trigger.enumerated() {
            append(String(character))
            if bubble, index >= 1, let snippet = snippet(trigger) {
                SuggestionBubbleController.shared.showDemo([.init(snippet: snippet, typedCount: index + 1)], highlighted: 0, at: caretRect)
            }
            try await pause(0.09)
        }
        try await pause(bubble ? 0.5 : 0.2)
        append(" ")
        try await pause(0.06)
        SuggestionBubbleController.shared.hide()
        replace(from: start, with: text + (state.addsSpaceAfterSnippet ? " " : ""))
        for style in [effect] + also { play(style, trigger: trigger, inserted: text) }
        try await pause(0.6)
    }

    /// Types the start of a shortcut, moves down the bubble with ↓ and takes one with Tab.
    private func chooseFromBubble(typed: String, choices: [String], pick: Int, effect: ReplacementAnimation) async throws {
        let start = length
        let snippets = choices.compactMap(snippet)
        for (index, character) in typed.enumerated() {
            append(String(character))
            if index >= 1 {
                SuggestionBubbleController.shared.showDemo(snippets.map { .init(snippet: $0, typedCount: index + 1) }, highlighted: 0, at: caretRect)
            }
            try await pause(0.1)
        }
        try await pause(0.6)
        for row in 1...max(pick, 1) where pick > 0 {
            SuggestionBubbleController.shared.showDemo(snippets.map { .init(snippet: $0, typedCount: typed.count) }, highlighted: row, at: caretRect)
            try await pause(0.55)
        }
        SuggestionBubbleController.shared.hide()
        let text = snippets[pick].expansion
        replace(from: start, with: text)
        play(effect, trigger: snippets[pick].trigger, inserted: text)
    }

    private func play(_ effect: ReplacementAnimation, trigger: String, inserted text: String) {
        guard let textView else { return }
        let end = length - (textView.string.hasSuffix(" ") ? 1 : 0)
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? text
        let lineStart = end - lastLine.utf16.count
        let line = textView.firstRect(forCharacterRange: NSRange(location: lineStart, length: lastLine.utf16.count), actualRange: nil)
        let caret = textView.firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
        OverlayPresenter.shared.play(effect, trigger: trigger, text: text,
                                     at: CaretLocator.Geometry(caret: CGRect(x: caret.minX, y: line.minY, width: 1, height: line.height), line: line))
    }

    private func snippet(_ trigger: String) -> Snippet? {
        state.store.snippets.first { $0.trigger == trigger }
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

extension Notification.Name {
    static let quillDemoPanel = Notification.Name("QuillDemoPanel")
}

private final class StageWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A plain backdrop with one document window on it.
private struct StageBackdrop: View {
    var body: some View {
        // GitHub's dark-mode page colour (#0d1117), so the GIFs blend into the README.
        Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)
    }
}

private struct StageView: View {
    let textView: NSTextView

    var body: some View {
        ZStack {
            StageBackdrop()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle().fill(color.opacity(0.85)).frame(width: 12, height: 12)
                    }
                    Spacer()
                    Text("Draft").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Color.clear.frame(width: 52, height: 1)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.bar)
                Divider()
                TextHost(textView: textView)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .padding(.horizontal, 56)
            .padding(.top, 72)
            .padding(.bottom, 24)
        }
    }
}

private struct TextHost: NSViewRepresentable {
    let textView: NSTextView

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {}
}
#endif
