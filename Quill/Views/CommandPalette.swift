import SwiftUI

/// ⌘K in the library: jump to any snippet or run any command, keyboard-first.
struct CommandPalette: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var highlighted = 0
    @State private var keyMonitor: Any?
    @FocusState private var isFieldFocused: Bool

    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let color: Color
        let action: () -> Void
    }

    private var commands: [Item] {
        var list: [Item] = [
            Item(id: "new", title: "New Snippet", subtitle: "⌘N", symbol: "square.and.pencil", color: .blue) { state.newSnippet() },
            Item(id: "group", title: "New Group", subtitle: "⇧⌘N", symbol: "folder.badge.plus", color: .teal) { state.newGroup() },
            Item(id: "overview", title: "Show Overview", subtitle: "⌘0", symbol: "chart.bar.xaxis", color: .purple) { state.selection = [.overview] },
            Item(id: "power", title: state.isOn ? "Turn Quill Off" : "Turn Quill On", subtitle: "⇧⌘P",
                 symbol: state.isOn ? "pause.circle" : "play.circle", color: state.isOn ? .orange : .green) { state.setOn(!state.isOn) },
            Item(id: "search", title: "Search and Insert Snippet", subtitle: "Floating panel", symbol: "magnifyingglass", color: .indigo) {
                NSApp.hide(nil)
                SearchPanelController.shared.show()
            },
            Item(id: "importMac", title: "Import Text Replacements from macOS", subtitle: "File menu", symbol: "square.and.arrow.down", color: .gray) { state.beginSystemImport() },
            Item(id: "import", title: "Import Snippets…", subtitle: "⇧⌘I", symbol: "tray.and.arrow.down", color: .gray) { state.isShowingFileImporter = true },
            Item(id: "export", title: "Export Snippets…", subtitle: "⇧⌘E", symbol: "tray.and.arrow.up", color: .gray) { state.exportLibrary() },
            Item(id: "settings", title: "Settings…", subtitle: "⌘,", symbol: "gearshape", color: .gray) { openSettings() },
        ]
        for order in SnippetSortOrder.allCases where order != state.sortOrder {
            list.append(Item(id: "sort-\(order.rawValue)", title: "Sort by \(order.title)", subtitle: "View",
                             symbol: "arrow.up.arrow.down", color: .gray) { state.sortOrder = order })
        }
        return list
    }

    private var snippetItems: [Item] {
        state.store.snippets
            .sorted(by: SnippetSortOrder.mostUsed.areInIncreasingOrder)
            .map { snippet in
                let group = state.store.group(for: snippet)
                return Item(id: snippet.id.uuidString,
                            title: snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger,
                            subtitle: snippet.preview,
                            symbol: snippet.symbol ?? group?.symbol ?? "text.quote",
                            color: group?.color.color ?? .accentColor) {
                    state.selection = [.snippet(snippet.id)]
                }
            }
    }

    private var items: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return Array(commands.prefix(5)) + Array(snippetItems.prefix(6))
        }
        let all = snippetItems + commands
        return Array(all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }.prefix(30))
    }

    var body: some View {
        let items = items

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "command")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                TextField("Type a command or a snippet", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .onSubmit { run(items) }
                    .onChange(of: query) { highlighted = 0 }
            }
            .padding(16)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if items.isEmpty {
                            Text("No Matches")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 30)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PaletteRow(title: item.title, subtitle: item.subtitle, symbol: item.symbol,
                                       color: item.color, isHighlighted: index == highlighted)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    highlighted = index
                                    run(items)
                                }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
            }
            .frame(height: 360)

            Divider()
            HStack(spacing: 14) {
                Text("↑↓ choose").font(.caption).foregroundStyle(.secondary)
                Text("↩ run").font(.caption).foregroundStyle(.secondary)
                Text("esc close").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 580)
        .onAppear {
            DispatchQueue.main.async { isFieldFocused = true }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125: highlighted = min(highlighted + 1, max(self.items.count - 1, 0)); return nil
                case 126: highlighted = max(highlighted - 1, 0); return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private func run(_ items: [Item]) {
        guard items.indices.contains(highlighted) else { return }
        let action = items[highlighted].action
        dismiss()
        DispatchQueue.main.async(execute: action)
    }
}

private struct PaletteRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            SnippetIcon(symbol: symbol, color: color, size: 26)
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(isHighlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
