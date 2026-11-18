import SwiftUI
import UniformTypeIdentifiers

/// The main window: Overview and snippets (loose and in groups) in the sidebar,
/// the dashboard or the selected snippet's editor beside them.
struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @State private var searchText = ""
    @State private var groupName = ""

    private var store: SnippetStore { state.store }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func visible(_ snippets: [Snippet]) -> [Snippet] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? snippets : snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.expansion.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted(by: state.sortOrder.areInIncreasingOrder)
    }

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 440)
        } detail: {
            detail
        }
        // Without a minimum, macOS can restore the window at a uselessly small size.
        .frame(minWidth: 760, minHeight: 460)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .sheet(isPresented: $state.isShowingPalette) {
            CommandPalette()
                .environment(state)
        }
        .sheet(item: $state.importSession) { session in
            ImportView(session: session)
                .environment(state)
        }
        .fileImporter(
            isPresented: $state.isShowingFileImporter,
            allowedContentTypes: [.json, .propertyList, .xml]
        ) { result in
            if case .success(let url) = result { state.importFile(url) }
        }
        .alert(
            state.alertMessage?.title ?? "",
            isPresented: Binding(
                get: { state.alertMessage != nil },
                set: { if !$0 { state.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.alertMessage?.message ?? "")
        }
        .alert("Rename Group", isPresented: Binding(
            get: { state.renamingGroupID != nil },
            set: { if !$0 { state.renamingGroupID = nil } }
        )) {
            TextField("Name", text: $groupName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = groupName.trimmingCharacters(in: .whitespaces)
                if let id = state.renamingGroupID, !name.isEmpty {
                    store.updateGroup(id) { $0.name = name }
                }
            }
        }
        .onChange(of: state.renamingGroupID) { _, id in
            groupName = id.flatMap(store.group)?.name ?? ""
        }
        .confirmationDialog(
            deletingGroupTitle,
            isPresented: Binding(
                get: { state.deletingGroupID != nil },
                set: { if !$0 { state.deletingGroupID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = state.deletingGroupID {
                Button("Keep Snippets") { store.deleteGroup(id, keepingSnippets: true) }
                Button("Delete Group and Snippets", role: .destructive) {
                    store.deleteGroup(id, keepingSnippets: false)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Keeping the snippets moves them out of the group.")
        }
        .tracksWindow(WindowID.library)
    }

    private var deletingGroupTitle: String {
        let name = state.deletingGroupID.flatMap(store.group)?.name ?? "Group"
        return "Delete \u{201C}\(name)\u{201D}?"
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var state = state
        let loose = visible(store.snippets(in: nil))

        return List(selection: $state.selection) {
            if state.status == .needsAccess {
                AccessCallout()
                    .listRowSeparator(.hidden)
            }

            if !isSearching {
                HStack(spacing: 10) {
                    SnippetIcon(symbol: "chart.bar.xaxis", color: .purple, size: 26)
                    Text("Overview").font(.body.weight(.medium))
                }
                .tag(SidebarItem.overview)
            }

            if !loose.isEmpty || store.groups.isEmpty {
                Section {
                    rows(for: loose)
                } header: {
                    DropHeader(groupID: nil) {
                        Text(store.groups.isEmpty ? "Snippets" : "Ungrouped")
                    }
                }
            }

            ForEach(store.groups) { group in
                let snippets = visible(store.snippets(in: group.id))
                if !isSearching || !snippets.isEmpty {
                    Section(isExpanded: isSearching ? .constant(true) : store.groupExpandedBinding(for: group.id)) {
                        rows(for: snippets)
                    } header: {
                        DropHeader(groupID: group.id) {
                            GroupHeader(group: group, count: store.snippets(in: group.id).count)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.snippets.isEmpty {
                ContentUnavailableView {
                    Label("No Snippets", systemImage: "pencil.line")
                } description: {
                    Text("Create a snippet, or bring in the text replacements you already use.")
                } actions: {
                    Button("New Snippet") { state.newSnippet() }
                    Button("Import from macOS") { state.beginSystemImport() }
                }
            } else if isSearching, store.snippets.allSatisfy({ visible([$0]).isEmpty }) {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.snippets.isEmpty {
                SidebarSummary(count: store.snippets.count, keysSaved: store.totalKeysSaved, sortOrder: $state.sortOrder)
            }
        }
        .onDeleteCommand {
            delete(state.selectedSnippetIDs)
        }
        .toolbar {
            ToolbarItemGroup {
                // A split button: click for a new snippet, or open the arrow for a new group.
                Menu {
                    Button("New Snippet", systemImage: "square.and.pencil") {
                        searchText = ""
                        state.newSnippet()
                    }
                    Button("New Group", systemImage: "folder.badge.plus") {
                        state.newGroup()
                    }
                } label: {
                    Label("New Snippet", systemImage: "square.and.pencil")
                } primaryAction: {
                    searchText = ""
                    state.newSnippet()
                }
                .help("New Snippet, or open the menu for a new group")
            }
        }
    }

    @ViewBuilder
    private func rows(for snippets: [Snippet]) -> some View {
        ForEach(snippets) { snippet in
            SnippetRow(
                snippet: snippet,
                group: store.group(for: snippet),
                isEnabled: store.enabledBinding(for: snippet.id),
                hasProblem: store.problem(with: snippet) != nil
            )
            .tag(SidebarItem.snippet(snippet.id))
            .draggable(SnippetDrag.payload(for: snippet.id)) {
                Label(snippet.trigger.isEmpty ? "Snippet" : snippet.trigger, systemImage: "text.quote")
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .contextMenu {
                SnippetActionsMenu(ids: contextIDs(for: snippet), onDelete: delete)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        let ids = state.selectedSnippetIDs
        if ids.count == 1, let id = ids.first, let binding = store.binding(for: id) {
            SnippetDetailView(snippet: binding) {
                delete([id])
            }
            .id(id)
        } else if ids.count > 1 {
            ContentUnavailableView {
                Label("\(ids.count) Snippets Selected", systemImage: "square.stack")
            } description: {
                Text("Right-click the selection to turn them on or off, move them to a group or change their animation.")
            } actions: {
                Button("Delete \(ids.count) Snippets", role: .destructive) {
                    delete(ids)
                }
            }
        } else {
            OverviewView()
        }
    }

    // MARK: Actions

    /// Right-clicking a selected row acts on the whole selection, like Finder.
    private func contextIDs(for snippet: Snippet) -> Set<Snippet.ID> {
        let selected = state.selectedSnippetIDs
        return selected.contains(snippet.id) ? selected : [snippet.id]
    }

    private func delete(_ ids: Set<Snippet.ID>) {
        store.delete(ids, undoManager: undoManager)
        state.selection.subtract(ids.map { .snippet($0) })
        if state.selection.isEmpty { state.selection = [.overview] }
    }
}

// MARK: - Rows

private struct GroupHeader: View {
    let group: SnippetGroup
    let count: Int
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: group.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(group.color.color.gradient, in: Circle())
                .accessibilityHidden(true)
            Text(group.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(group.color.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(group.color.color.opacity(0.16), in: Capsule())
            Spacer()
            Toggle("Turn \(group.name) on or off", isOn: state.store.groupEnabledBinding(for: group.id))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(group.isEnabled ? "Turn Group Off" : "Turn Group On")
        }
        .opacity(group.isEnabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .contextMenu {
            GroupActionsMenu(group: group)
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let group: SnippetGroup?
    @Binding var isEnabled: Bool
    let hasProblem: Bool

    private var isActive: Bool { snippet.isEnabled && (group?.isEnabled ?? true) }

    var body: some View {
        HStack(spacing: 10) {
            SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: group?.color.color ?? .accentColor, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(snippet.trigger.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if snippet.mode == .immediate {
                        Image(systemName: "bolt.fill")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .help("Expands immediately")
                            .accessibilityLabel("Expands immediately")
                    }
                    if TokenRenderer.containsTokens(snippet.expansion) {
                        Image(systemName: "curlybraces")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .help("Contains tokens")
                            .accessibilityLabel("Contains tokens")
                    }
                    if hasProblem {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Needs attention")
                    }
                }
                Text(snippet.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(isActive ? 1 : 0.45)

            Spacer(minLength: 4)

            Toggle("Turn \(snippet.trigger) on or off", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(snippet.isEnabled ? "Turn Off" : "Turn On")
        }
        .padding(.vertical, 4)
    }
}

/// A snippet's icon in a small rounded square, tinted with its group's colour.
struct SnippetIcon: View {
    let symbol: String?
    let color: Color?
    var size: CGFloat = 24

    var body: some View {
        let fill = color ?? .accentColor
        Image(systemName: symbol ?? "text.quote")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [fill.opacity(0.85), fill], startPoint: .top, endPoint: .bottom))
                    .shadow(color: fill.opacity(0.35), radius: size * 0.12, y: size * 0.05)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct SidebarSummary: View {
    let count: Int
    let keysSaved: Int
    @Binding var sortOrder: SnippetSortOrder

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(SnippetSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort By \(sortOrder.title)", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort By: \(sortOrder.title)")

                Text("\(count) \(count == 1 ? "snippet" : "snippets")")
                Spacer()
                Text("\(keysSaved.formatted()) keys saved")
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// Shown at the top of the sidebar until Quill has Accessibility access.
private struct AccessCallout: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Quill Is Off", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Allow access so Quill can expand snippets.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Open Privacy Settings…") {
                state.requestAccess()
                state.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Drag and drop

enum SnippetDrag {
    static let prefix = "quill-snippet:"

    static func payload(for id: Snippet.ID) -> String { prefix + id.uuidString }

    static func snippetID(from payload: String) -> Snippet.ID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

/// A section header that accepts dropped snippets (to move them into its group) and
/// dropped text from other apps (to make a new snippet there). Highlights while targeted.
private struct DropHeader<Content: View>: View {
    let groupID: SnippetGroup.ID?
    @ViewBuilder let content: Content
    @Environment(AppState.self) private var state
    @State private var isTargeted = false

    var body: some View {
        content
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isTargeted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: String.self) { items, _ in
                state.handleDrop(items, into: groupID)
            } isTargeted: { isTargeted = $0 }
    }
}
