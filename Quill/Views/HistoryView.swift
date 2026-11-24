import SwiftUI

/// Recent expansions, newest first, grouped by day. Search, filter by app or snippet,
/// copy the text again or jump to the snippet.
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<HistoryEntry.ID>()
    @State private var isConfirmingClear = false
    @State private var filter = HistoryFilter()

    private var entries: [HistoryEntry] { filter.apply(to: state.history.entries) }

    private func days(_ entries: [HistoryEntry]) -> [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        let entries = entries

        Group {
            if !state.keepsHistory {
                ContentUnavailableView {
                    Label("History Is Off", systemImage: "clock.badge.xmark")
                } description: {
                    Text("Quill isn't recording expansions.")
                } actions: {
                    Button("Turn On History") { state.keepsHistory = true }
                }
            } else if state.history.entries.isEmpty {
                ContentUnavailableView("No Expansions Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Each quill you expand appears here, newest first."))
            } else {
                VStack(spacing: 0) {
                    summaryBar(entries)
                    Divider()
                    if entries.isEmpty {
                        ContentUnavailableView.search(text: filter.query)
                            .frame(maxHeight: .infinity)
                    } else {
                        List(selection: $selection) {
                            ForEach(days(entries), id: \.day) { day in
                                Section {
                                    ForEach(day.entries) { entry in
                                        HistoryRow(entry: entry)
                                            .tag(entry.id)
                                            .contextMenu { menu(for: entry) }
                                    }
                                } header: {
                                    HStack {
                                        Text(sectionTitle(day.day))
                                        Spacer()
                                        Text("\(day.entries.count)")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .onDeleteCommand { state.history.remove(selection) }
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $filter.query, placement: .toolbar, prompt: "Search History")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                Button("Clear History", systemImage: "trash") { isConfirmingClear = true }
                    .help("Clear History")
                    .disabled(state.history.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear all expansion history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { state.history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the list only. Your quills and usage counts stay.")
        }
    }

    // MARK: Summary and filters

    private func summaryBar(_ entries: [HistoryEntry]) -> some View {
        let apps = Set(entries.compactMap { $0.bundleID ?? $0.appName }).count
        return HStack(spacing: 8) {
            Text("History")
                .font(.system(size: 26, weight: .bold))
            Spacer()
            if let bundleID = filter.bundleID {
                FilterChip(title: appName(for: bundleID), symbol: "app") { filter.bundleID = nil }
            }
            if let id = filter.snippetID {
                FilterChip(title: state.store.snippet(id)?.trigger ?? "Quill", symbol: "text.quote") { filter.snippetID = nil }
            }
            Text("\(entries.count) \(entries.count == 1 ? "expansion" : "expansions") · \(apps) \(apps == 1 ? "app" : "apps")")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var filterMenu: some View {
        let entries = state.history.entries
        let apps = QuillStats.topApps(entries, limit: 20)
        let snippetIDs = entries.map(\.snippetID).reduce(into: [Snippet.ID]()) { list, id in if !list.contains(id) { list.append(id) } }

        return Menu {
            Picker("App", selection: $filter.bundleID) {
                Text("All Apps").tag(String?.none)
                Divider()
                ForEach(apps) { app in
                    Text("\(app.name) (\(app.uses))").tag(Optional(app.bundleID ?? app.name))
                }
            }
            Picker("Quill", selection: $filter.snippetID) {
                Text("All Quills").tag(Snippet.ID?.none)
                Divider()
                ForEach(snippetIDs, id: \.self) { id in
                    Text(state.store.snippet(id)?.trigger ?? "Deleted Quill").tag(Optional(id))
                }
            }
            if filter.isActive {
                Divider()
                Button("Clear Filters") { filter = HistoryFilter() }
            }
        } label: {
            Label("Filter", systemImage: filter.bundleID != nil || filter.snippetID != nil
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter by App or Quill")
        .accessibilityIdentifier("history-filter")
    }

    private func appName(for bundleID: String) -> String {
        state.history.entries.first { $0.bundleID == bundleID }?.appName ?? AppInfo.name(for: bundleID)
    }

    private func sectionTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: Menu

    @ViewBuilder
    private func menu(for entry: HistoryEntry) -> some View {
        Button("Copy Text", systemImage: "doc.on.doc") { copy(entry) }
        if state.store.snippet(entry.snippetID) != nil {
            Button("Show Quill", systemImage: "arrow.right.circle") {
                state.page = .snippets
                state.selection = [.snippet(entry.snippetID)]
            }
        }
        Divider()
        if let bundleID = entry.bundleID {
            Button("Only \(entry.appName ?? "This App")", systemImage: "app") { filter.bundleID = bundleID }
        }
        Button("Only \u{201C}\(entry.trigger)\u{201D}", systemImage: "text.quote") { filter.snippetID = entry.snippetID }
        Divider()
        Button("Remove from History", systemImage: "trash", role: .destructive) {
            state.history.remove(selection.contains(entry.id) ? selection : [entry.id])
        }
    }

    private func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .lineLimit(1)
            Button("Remove Filter", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @Environment(AppState.self) private var state
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        let snippet = state.store.snippet(entry.snippetID)
        let group = snippet.flatMap(state.store.group(for:))

        HStack(spacing: 12) {
            SnippetIcon(symbol: snippet?.symbol ?? group?.symbol, color: snippet.map(state.store.tint(for:)) ?? .gray, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.trigger)
                        .font(.body.monospaced().weight(.semibold))
                    if let appName = entry.appName {
                        HStack(spacing: 4) {
                            AppIconView(bundleID: entry.bundleID, size: 14)
                            Text(appName)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if snippet == nil {
                        Text("Deleted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isHovering {
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    copied = true
                }
                .controlSize(.small)
                .help("Copy the text again")
            }
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if !hovering { copied = false }
        }
        .accessibilityElement(children: .combine)
    }
}
