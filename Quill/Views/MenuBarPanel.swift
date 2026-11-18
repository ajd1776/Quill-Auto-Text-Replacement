import SwiftUI

/// The panel shown from Quill's menu bar icon: status, search, filters, and every snippet
/// with a switch. Click a snippet to type it into the app you were using.
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: Filter = .all
    @AppStorage("menuBarSort") private var sort: SnippetSortOrder = .recentlyUsed
    @FocusState private var isSearchFocused: Bool

    private var store: SnippetStore { state.store }

    enum Filter: Hashable {
        case all, on, off, group(SnippetGroup.ID)
    }

    private struct ListKey: Hashable {
        let query: String
        let filter: Filter
    }

    private var snippets: [Snippet] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return store.snippets
            .filter { snippet in
                switch filter {
                case .all: true
                case .on: store.isActive(snippet)
                case .off: !store.isActive(snippet)
                case .group(let id): snippet.groupID == id
                }
            }
            .filter {
                text.isEmpty
                    || $0.trigger.localizedCaseInsensitiveContains(text)
                    || $0.expansion.localizedCaseInsensitiveContains(text)
            }
            .sorted(by: sort.areInIncreasingOrder)
    }

    var body: some View {
        let snippets = snippets

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if let update = state.updates.availableUpdate {
                Button {
                    openLibrary()
                    state.updates.isShowingDetails = true
                } label: {
                    Label("Quill \(update.version) is available", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            searchBar
                .padding(.horizontal, 12)

            chips
                .padding(.vertical, 8)

            Divider()

            if snippets.isEmpty {
                ContentUnavailableView {
                    Label(store.snippets.isEmpty ? "No Snippets" : "No Matches", systemImage: "text.magnifyingglass")
                } description: {
                    Text(store.snippets.isEmpty ? "Make one in the library." : "Try another search or filter.")
                }
                .frame(height: 330)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(snippets) { snippet in
                            PanelRow(snippet: snippet, group: store.group(for: snippet)) {
                                insert(snippet)
                            }
                        }
                    }
                    .padding(6)
                }
                // A fresh list for each search or filter: no cross-fading rows, and it starts at the top.
                .id(ListKey(query: query, filter: filter))
                .transaction { $0.animation = nil }
                .frame(height: 330)
            }

            Divider()

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 360)
        .onAppear {
            state.setSearchPanelOpen(true)
            isSearchFocused = true
        }
        .onDisappear {
            state.setSearchPanelOpen(false)
            query = ""
        }
        #if DEBUG
        // The scripted demo types into the search field and taps the filters.
        .onReceive(NotificationCenter.default.publisher(for: .quillDemoPanel)) { note in
            withAnimation(.snappy) {
                if let text = note.userInfo?["query"] as? String { query = text }
                switch note.userInfo?["filter"] as? String {
                case "all": filter = .all
                case "on": filter = .on
                case "off": filter = .off
                case let name?:
                    if let group = store.groups.first(where: { $0.name == name }) { filter = .group(group.id) }
                case nil: break
                }
            }
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            Image(nsImage: state.menuBarIcon.image(isOn: state.isOn))
                .renderingMode(.template)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(statusColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Quill").font(.headline)
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if state.status == .needsAccess {
                Button("Allow Access") {
                    state.requestAccess()
                    state.openAccessibilitySettings()
                }
                .controlSize(.small)
            } else {
                Menu {
                    if state.isPaused {
                        Button("Resume Now", systemImage: "play.fill") { state.setOn(true) }
                        Divider()
                    }
                    Button("Pause for 15 Minutes") { state.pause(minutes: 15) }
                    Button("Pause for 1 Hour") { state.pause(minutes: 60) }
                    Button("Pause Until Tomorrow Morning") { state.pauseUntilTomorrowMorning() }
                    if let app = state.lastExternalApp, let bundleID = app.bundleIdentifier {
                        Divider()
                        Toggle("Pause in \(app.localizedName ?? "This App")", isOn: Binding(
                            get: { state.isExcluded(bundleID) },
                            set: { state.setExcluded(bundleID, $0) }
                        ))
                    }
                } label: {
                    Image(systemName: "pause.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Pause")

                Toggle("Quill On", isOn: Binding(get: { state.isOn }, set: { state.setOn($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(state.isOn ? "Turn Quill Off" : "Turn Quill On")
            }
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .on: .accentColor
        case .off: .gray
        case .pausedUntil, .pausedInApp: .orange
        case .needsAccess: .red
        }
    }

    private var statusTitle: String {
        switch state.status {
        case .on:
            let count = store.activeSnippets.count
            return "On · \(count) \(count == 1 ? "snippet" : "snippets")"
        case .off:
            return "Off"
        case .pausedUntil(let date):
            return "Paused until \(date.formatted(date: .omitted, time: .shortened))"
        case .pausedInApp(let name):
            return "Paused in \(name)"
        case .needsAccess:
            return "Needs Accessibility access"
        }
    }

    // MARK: Search and filters

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search snippets", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = snippets.first { insert(first) }
                }
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(SnippetSortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "All", color: .accentColor, isSelected: filter == .all) { filter = .all }
                Chip(title: "On", color: .green, isSelected: filter == .on) { filter = .on }
                Chip(title: "Off", color: .gray, isSelected: filter == .off) { filter = .off }
                ForEach(store.groups) { group in
                    Chip(title: group.name, color: group.tint, isSelected: filter == .group(group.id)) {
                        filter = .group(group.id)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(title: "New Snippet", symbol: "square.and.pencil") {
                openLibrary()
                state.page = .snippets
                state.newSnippet()
            }
            FooterButton(title: "Library", symbol: "books.vertical") {
                state.page = .snippets
                openLibrary()
            }
            FooterButton(title: "Stats", symbol: "chart.bar") {
                state.page = .stats
                openLibrary()
            }
            FooterButton(title: "Settings", symbol: "gearshape") {
                state.page = .settings
                openLibrary()
            }
            Spacer()
            FooterButton(title: "Quit", symbol: "power") { NSApp.terminate(nil) }
        }
    }

    /// Closes the panel, hands focus back to the app you were typing in, then types the snippet.
    private func insert(_ snippet: Snippet) {
        closePanel()
        state.lastExternalApp?.activate()
        state.insert(snippet, after: 0.3)
    }

    private func closePanel() {
        dismiss()
        if let window = NSApp.keyWindow, window.className.contains("MenuBarExtra") { window.close() }
    }

    private func openLibrary() {
        closePanel()
        NSApp.activate()
        openWindow(id: WindowID.library)
    }
}

// MARK: - Pieces

private struct PanelRow: View {
    let snippet: Snippet
    let group: SnippetGroup?
    let insert: () -> Void
    @Environment(AppState.self) private var state
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: insert) {
                HStack(spacing: 10) {
                    SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: group?.tint ?? .accentColor, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
                            .font(.callout.monospaced().weight(.semibold))
                            .lineLimit(1)
                        Text(snippet.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(state.store.isActive(snippet) ? 1 : 0.5)
            .help("Insert \u{201C}\(snippet.trigger)\u{201D}")

            Toggle("Turn \(snippet.trigger) on or off", isOn: state.store.enabledBinding(for: snippet.id))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
    }
}

private struct Chip: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 26)
                .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }
}
