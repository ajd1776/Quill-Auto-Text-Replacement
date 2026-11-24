import SwiftUI

/// A practice page for trying quills: type in the text area and they fire for real,
/// with a cheat sheet to click, a hit counter and an effect to try. Practice never
/// counts towards Stats or History.
struct FiringRangeView: View {
    @Environment(AppState.self) private var state
    @State private var text = ""
    @State private var search = ""
    @FocusState private var isTyping: Bool

    private var quills: [Snippet] {
        let active = state.store.activeSnippets.sorted { $0.trigger.localizedStandardCompare($1.trigger) == .orderedAscending }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return active }
        return active.filter { $0.trigger.localizedCaseInsensitiveContains(query) || $0.expansion.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                if state.status == .needsAccess { accessNotice }
                scoreboard
                practiceArea
            }
            .padding(20)
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            cheatSheet
                .frame(width: 320)
        }
        .navigationTitle("Firing Range")
        .toolbar {
            ToolbarItem {
                Picker("Effect", selection: Binding(
                    get: { state.rangeEffect },
                    set: { state.rangeEffect = $0 }
                )) {
                    Text("Each Quill's Own Effect").tag(ReplacementAnimation?.none)
                    Divider()
                    ForEach(ReplacementAnimation.allCases) { effect in
                        Label(effect.title, systemImage: effect.symbol).tag(Optional(effect))
                    }
                }
                .help("The effect every quill uses here. Your quills' own effects aren't changed.")
            }
            ToolbarItem {
                Button("Clear", systemImage: "eraser") {
                    text = ""
                    state.rangeHits.removeAll()
                    isTyping = true
                }
                .help("Clear the text and the hit counter")
            }
        }
        .onAppear { isTyping = true }
        .onChange(of: isTyping, initial: true) { _, focused in state.isPracticeFocused = focused }
        .onDisappear { state.isPracticeFocused = false }
    }

    // MARK: Practice

    private var accessNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Quills can't fire until Quill has Accessibility access.")
            Spacer()
            Button("Allow Access…") { state.requestAccess() }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scoreboard: some View {
        HStack(spacing: 12) {
            ScoreTile(title: "Hits", value: state.rangeHits.count.formatted(), symbol: "scope")
            ScoreTile(title: "Keys Saved", value: state.rangeHits.reduce(0) { $0 + $1.keysSaved }.formatted(), symbol: "keyboard")
            ScoreTile(title: "Effect", value: state.rangeEffect?.title ?? "Own", symbol: state.rangeEffect?.symbol ?? "sparkles")
        }
    }

    private var practiceArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practice")
                .font(.headline)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .focused($isTyping)
                .background(Surface.editor, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type a shortcut, such as \(state.store.activeSnippets.first?.trigger ?? "eml"), then a space.")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Practice text")
                .accessibilityIdentifier("range-practice")
            Text("Nothing you type here is saved, and practice doesn't count towards Stats or History.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Cheat sheet

    private var cheatSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Quills", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Surface.card, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)

            List {
                Section("Your Quills") {
                    ForEach(quills) { quill in
                        Button { fire(quill) } label: {
                            CheatRow(quill: quill, tint: state.store.tint(for: quill), symbol: quill.symbol ?? state.store.group(for: quill)?.symbol)
                        }
                        .buttonStyle(.plain)
                        .help("Fire \(quill.trigger) into the practice text")
                        .accessibilityHint("Types its text into the practice area")
                    }
                    if quills.isEmpty {
                        Text(search.isEmpty ? "No quills are switched on." : "No matches.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !state.rangeHits.isEmpty {
                    Section("Recent Hits") {
                        ForEach(state.rangeHits.prefix(8)) { hit in
                            HStack {
                                Text(hit.trigger).font(.body.monospaced())
                                Spacer()
                                Text("\(hit.keysSaved) keys saved")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(Surface.sidebar)
    }

    /// Puts the cursor back in the practice text, then types the quill there.
    private func fire(_ quill: Snippet) {
        isTyping = true
        state.insert(quill, after: 0.15)
    }
}

private struct ScoreTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Surface.card, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct CheatRow: View {
    let quill: Snippet
    let tint: Color
    let symbol: String?

    var body: some View {
        HStack(spacing: 10) {
            SnippetIcon(symbol: symbol, color: tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(quill.trigger)
                    .font(.body.monospaced().weight(.medium))
                Text(quill.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
