import SwiftUI

/// Recent expansions, newest first, grouped by day.
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<HistoryEntry.ID>()
    @State private var isConfirmingClear = false

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: state.history.entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
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
                                       description: Text("Each snippet you expand appears here, newest first."))
            } else {
                List(selection: $selection) {
                    ForEach(days, id: \.day) { day in
                        Section(sectionTitle(day.day)) {
                            ForEach(day.entries) { entry in
                                HistoryRow(entry: entry)
                                    .tag(entry.id)
                                    .contextMenu { menu(for: entry) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand { state.history.remove(selection) }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear History", systemImage: "trash") { isConfirmingClear = true }
                    .help("Clear History")
                    .disabled(state.history.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear all expansion history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { state.history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the list only. Your snippets and usage counts stay.")
        }
    }

    private func sectionTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder
    private func menu(for entry: HistoryEntry) -> some View {
        Button("Copy Text", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
        }
        if state.store.snippet(entry.snippetID) != nil {
            Button("Show Snippet", systemImage: "arrow.right.circle") {
                state.selection = [.snippet(entry.snippetID)]
            }
        }
        Divider()
        Button("Remove from History", systemImage: "trash", role: .destructive) {
            state.history.remove(selection.contains(entry.id) ? selection : [entry.id])
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @Environment(AppState.self) private var state

    var body: some View {
        let snippet = state.store.snippet(entry.snippetID)
        let group = snippet.flatMap(state.store.group(for:))

        HStack(spacing: 12) {
            SnippetIcon(symbol: snippet?.symbol ?? group?.symbol, color: group?.tint ?? .accentColor, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.trigger)
                        .font(.body.monospaced().weight(.semibold))
                    if let appName = entry.appName {
                        HStack(spacing: 4) {
                            if let bundleID = entry.bundleID,
                               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .accessibilityHidden(true)
                            }
                            Text(appName)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Text(entry.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
