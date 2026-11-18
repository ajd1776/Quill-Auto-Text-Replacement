import SwiftUI
import UniformTypeIdentifiers

/// The main window. Toolbar tabs switch between Snippets, Stats, History and Settings.
struct LibraryView: View {
    @Environment(AppState.self) private var state
    @State private var groupName = ""

    private var store: SnippetStore { state.store }

    var body: some View {
        @Bindable var state = state

        Group {
            switch state.page {
            case .snippets: SnippetsPage()
            case .stats: OverviewView()
            case .history: HistoryView()
            case .settings: SettingsPage()
            }
        }
        // Without a minimum, macOS can restore the window at a uselessly small size.
        .frame(minWidth: 1180, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: $state.page) {
                    ForEach(AppPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Switch Page")
            }
        }
        .sheet(isPresented: Binding(
            get: { state.updates.isShowingDetails && state.updates.availableUpdate != nil },
            set: { state.updates.isShowingDetails = $0 }
        )) {
            if let update = state.updates.availableUpdate {
                UpdateSheet(release: update)
                    .environment(state)
            }
        }
        .sheet(isPresented: Binding(
            get: { state.colorPickerGroupID != nil },
            set: { if !$0 { state.colorPickerGroupID = nil } }
        )) {
            if let id = state.colorPickerGroupID {
                GroupColorPicker(groupID: id)
                    .environment(state)
            }
        }
        .sheet(isPresented: $state.isShowingPacks) {
            PackGallery()
                .environment(state)
        }
        .sheet(item: $state.iconPickerTarget) { target in
            iconPickerSheet(for: target)
        }
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
                Button("Keep Snippets") {
                    store.deleteGroup(id, keepingSnippets: true)
                    state.scope = .all
                }
                Button("Delete Group and Snippets", role: .destructive) {
                    store.deleteGroup(id, keepingSnippets: false)
                    state.scope = .all
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

    @ViewBuilder
    private func iconPickerSheet(for target: AppState.IconTarget) -> some View {
        switch target {
        case .group(let id):
            let group = store.group(id)
            IconPicker(current: group?.symbol, tint: group?.tint ?? .accentColor) { icon in
                if let icon { store.updateGroup(id) { $0.symbol = icon } }
            }
        case .snippet(let id):
            let snippet = store.snippet(id)
            let group = snippet.flatMap(store.group(for:))
            IconPicker(current: snippet?.symbol, tint: group?.tint ?? .accentColor, defaultTitle: "Use Group Icon") { icon in
                store.update(id) { $0.symbol = icon }
            }
        }
    }
}

// MARK: - Snippets page

/// Filters and groups in the sidebar, snippets as a list or grid, the editor in an inspector.
struct SnippetsPage: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @State private var searchText = ""
    @AppStorage("snippetLayout") private var layout: SnippetLayout = .list

    private var store: SnippetStore { state.store }

    private var visibleSnippets: [Snippet] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let scoped = state.snippets(in: state.scope)
        let matching = query.isEmpty ? scoped : scoped.filter {
            $0.trigger.localizedCaseInsensitiveContains(query) || $0.expansion.localizedCaseInsensitiveContains(query)
        }
        let order: SnippetSortOrder = state.scope == .recent ? .recentlyUsed : state.sortOrder
        return matching.sorted(by: order.areInIncreasingOrder)
    }

    private var editedSnippetID: Snippet.ID? {
        state.selectedSnippetIDs.count == 1 ? state.selectedSnippetIDs.first : nil
    }

    var body: some View {
        @Bindable var state = state
        let snippets = visibleSnippets

        NavigationSplitView {
            SnippetsSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            Group {
                if store.snippets.isEmpty {
                    ContentUnavailableView {
                        Label("No Snippets", systemImage: "text.quote")
                    } description: {
                        Text("Create a snippet, add a starter pack, or bring in the text replacements you already use.")
                    } actions: {
                        Button("New Snippet") { state.newSnippet() }
                            .primaryActionStyle()
                        Button("Add Starter Pack…") { state.isShowingPacks = true }
                        Button("Import from macOS") { state.beginSystemImport() }
                    }
                } else if snippets.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("Nothing Here", systemImage: "tray",
                                               description: Text("No snippets match \u{201C}\(state.title(for: state.scope))\u{201D}."))
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else if layout == .grid {
                    SnippetGrid(snippets: snippets, onDelete: delete)
                } else {
                    SnippetList(snippets: snippets, onDelete: delete)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ScopeHeader(count: snippets.count)
            }
            .frame(minWidth: 460)
            .navigationTitle(state.title(for: state.scope))
            .toolbar(removing: .title)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Snippets")
        .inspector(isPresented: Binding(
            get: { editedSnippetID != nil },
            set: { if !$0 { state.selection = [] } }
        )) {
            Group {
                if let id = editedSnippetID, let binding = store.binding(for: id) {
                    SnippetDetailView(snippet: binding) { delete([id]) }
                        .id(id)
                }
            }
            .inspectorColumnWidth(min: 360, ideal: 400, max: 640)
        }
        .onDeleteCommand { delete(state.selectedSnippetIDs) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("View As", selection: $layout) {
                        Label("List", systemImage: "list.bullet").tag(SnippetLayout.list)
                        Label("Grid", systemImage: "square.grid.2x2").tag(SnippetLayout.grid)
                    }
                    .pickerStyle(.inline)
                    Picker("Sort By", selection: $state.sortOrder) {
                        ForEach(SnippetSortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("View Options", systemImage: layout == .grid ? "square.grid.2x2" : "list.bullet")
                }
                .help("View as List or Grid, and Sort")

                Menu {
                    Button("New Snippet", systemImage: "square.and.pencil") { state.newSnippet() }
                    Button("New Group", systemImage: "folder.badge.plus") { state.newGroup() }
                    Divider()
                    Button("Add Starter Pack…", systemImage: "shippingbox") { state.isShowingPacks = true }
                    Button("Import Text Replacements…", systemImage: "square.and.arrow.down") { state.beginSystemImport() }
                } label: {
                    Label("New Snippet", systemImage: "plus")
                } primaryAction: {
                    searchText = ""
                    state.newSnippet()
                }
                .help("New Snippet (open the menu for more)")
            }
        }
    }

    private func delete(_ ids: Set<Snippet.ID>) {
        store.delete(ids, undoManager: undoManager)
        state.selection.subtract(ids.map { .snippet($0) })
    }
}

// MARK: Sidebar

private struct SnippetsSidebar: View {
    @Environment(AppState.self) private var state

    private var store: SnippetStore { state.store }

    var body: some View {
        @Bindable var state = state

        List(selection: Binding(
            get: { state.scope },
            set: { if let scope = $0 { state.scope = scope; state.selection = [] } }
        )) {
            if state.status == .needsAccess {
                AccessCallout()
                    .listRowSeparator(.hidden)
            }
            if let update = state.updates.availableUpdate {
                UpdateBanner(release: update)
                    .listRowSeparator(.hidden)
            }

            Section("Library") {
                ScopeRow(title: "All Snippets", symbol: "tray.full.fill", color: .accentColor, count: state.snippets(in: .all).count)
                    .tag(SnippetScope.all)
                ScopeRow(title: "Recently Used", symbol: "clock.fill", color: .orange, count: state.snippets(in: .recent).count)
                    .tag(SnippetScope.recent)
                ScopeRow(title: "On", symbol: "checkmark.circle.fill", color: .green, count: state.snippets(in: .enabled).count)
                    .tag(SnippetScope.enabled)
                ScopeRow(title: "Off", symbol: "pause.circle.fill", color: .gray, count: state.snippets(in: .disabled).count)
                    .tag(SnippetScope.disabled)
                ScopeRow(title: "With Tokens", symbol: "curlybraces", color: .indigo, count: state.snippets(in: .tokens).count)
                    .tag(SnippetScope.tokens)
            }

            Section {
                ForEach(store.groups) { group in
                    DropTarget(groupID: group.id) {
                        GroupRow(group: group, count: store.snippets(in: group.id).count)
                    }
                    .tag(SnippetScope.group(group.id))
                }
                DropTarget(groupID: nil) {
                    ScopeRow(title: "Ungrouped", symbol: "tray", color: .gray, count: store.snippets(in: nil).count)
                }
                .tag(SnippetScope.ungrouped)
            } header: {
                HStack {
                    Text("Groups")
                    Spacer()
                    Button("New Group", systemImage: "plus") { state.newGroup() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("New Group")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }
}

/// The list's title and count, large like Reminders, tinted with the group colour.
private struct ScopeHeader: View {
    let count: Int
    @Environment(AppState.self) private var state

    private var tint: Color {
        if case .group(let id) = state.scope { return state.store.group(id)?.tint ?? .accentColor }
        return .primary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.title(for: state.scope))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint == .primary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                .accessibilityLabel("\(count) snippets")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct ScopeRow: View {
    let title: String
    let symbol: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            SnippetIcon(symbol: symbol, color: color, size: 22)
            Text(title)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct GroupRow: View {
    let group: SnippetGroup
    let count: Int
    @Environment(AppState.self) private var state
    @State private var isPickingIcon = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Button {
                isPickingIcon = true
            } label: {
                SnippetIcon(symbol: group.symbol, color: group.tint, size: 22)
            }
            .buttonStyle(.plain)
            .help("Change Icon")
            .popover(isPresented: $isPickingIcon, arrowEdge: .trailing) {
                IconPicker(current: group.symbol, tint: group.tint) { icon in
                    if let icon { state.store.updateGroup(group.id) { $0.symbol = icon } }
                }
            }

            Text(group.name)
                .lineLimit(1)
            Spacer(minLength: 4)

            if isHovering {
                Menu {
                    GroupActionsMenu(group: group)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Group Options")
                .accessibilityLabel("Options for \(group.name)")
            } else {
                Text("\(count)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Toggle("Turn \(group.name) on or off", isOn: state.store.groupEnabledBinding(for: group.id))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(group.isEnabled ? "Turn Group Off" : "Turn Group On")
        }
        .padding(.vertical, 2)
        .opacity(group.isEnabled ? 1 : 0.55)
        .onHover { isHovering = $0 }
        .contextMenu { GroupActionsMenu(group: group) }
    }
}

private struct SidebarFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button("New Group", systemImage: "folder.badge.plus") { state.newGroup() }
                    .help("New Group")
                Button("Starter Packs", systemImage: "shippingbox") { state.isShowingPacks = true }
                    .help("Add a Starter Pack")
                Button("Settings", systemImage: "gearshape") { state.page = .settings }
                    .help("Settings (⌘,)")
                Spacer()
                Text("\(state.store.totalKeysSaved.formatted()) keys saved")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

// MARK: List and grid

private struct SnippetList: View {
    let snippets: [Snippet]
    let onDelete: (Set<Snippet.ID>) -> Void
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            ForEach(snippets) { snippet in
                SnippetRow(snippet: snippet, group: state.store.group(for: snippet),
                           isEnabled: state.store.enabledBinding(for: snippet.id),
                           hasProblem: state.store.problem(with: snippet) != nil)
                    .tag(SidebarItem.snippet(snippet.id))
                    .snippetInteractions(snippet, onDelete: onDelete)
            }
        }
        .listStyle(.inset)
    }
}

private struct SnippetGrid: View {
    let snippets: [Snippet]
    let onDelete: (Set<Snippet.ID>) -> Void
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)], spacing: 14) {
                ForEach(snippets) { snippet in
                    SnippetCard(snippet: snippet, group: state.store.group(for: snippet),
                                isSelected: state.selectedSnippetIDs.contains(snippet.id))
                        .onTapGesture {
                            let item = SidebarItem.snippet(snippet.id)
                            if NSEvent.modifierFlags.contains(.command) {
                                if state.selection.contains(item) { state.selection.remove(item) } else { state.selection.insert(item) }
                            } else {
                                state.selection = [item]
                            }
                        }
                        .snippetInteractions(snippet, onDelete: onDelete)
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { state.selection = [] }
    }
}

private extension View {
    /// Drag to a group, and the right-click menu.
    func snippetInteractions(_ snippet: Snippet, onDelete: @escaping (Set<Snippet.ID>) -> Void) -> some View {
        modifier(SnippetInteractions(snippet: snippet, onDelete: onDelete))
    }
}

private struct SnippetInteractions: ViewModifier {
    let snippet: Snippet
    let onDelete: (Set<Snippet.ID>) -> Void
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content
            .draggable(SnippetDrag.payload(for: snippet.id)) {
                Label(snippet.trigger.isEmpty ? "Snippet" : snippet.trigger, systemImage: "text.quote")
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .contextMenu {
                let selected = state.selectedSnippetIDs
                SnippetActionsMenu(ids: selected.contains(snippet.id) ? selected : [snippet.id], onDelete: onDelete)
            }
    }
}

/// A snippet as a card in the grid.
private struct SnippetCard: View {
    let snippet: Snippet
    let group: SnippetGroup?
    let isSelected: Bool
    @Environment(AppState.self) private var state
    @State private var isHovering = false

    private var tint: Color { group?.tint ?? .accentColor }
    private var isActive: Bool { state.store.isActive(snippet) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: tint, size: 38)
                Spacer()
                Toggle("Turn \(snippet.trigger) on or off", isOn: state.store.enabledBinding(for: snippet.id))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    if snippet.mode == .immediate {
                        Image(systemName: "bolt.fill").imageScale(.small).foregroundStyle(.secondary)
                            .accessibilityLabel("Expands immediately")
                    }
                    if state.store.problem(with: snippet) != nil {
                        Image(systemName: "exclamationmark.triangle.fill").imageScale(.small).foregroundStyle(.orange)
                            .accessibilityLabel("Needs attention")
                    }
                }
                Text(snippet.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            HStack(spacing: 6) {
                if let group {
                    Text(group.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.14), in: Capsule())
                }
                Spacer()
                Label(snippet.useCount.formatted(), systemImage: "arrow.uturn.right")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Used \(snippet.useCount) times")
            }
        }
        .padding(14)
        .opacity(isActive ? 1 : 0.55)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.18 : 0.08), radius: isHovering ? 8 : 3, y: isHovering ? 3 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let group: SnippetGroup?
    @Binding var isEnabled: Bool
    let hasProblem: Bool

    private var isActive: Bool { snippet.isEnabled && (group?.isEnabled ?? true) }

    var body: some View {
        HStack(spacing: 12) {
            SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: group?.tint ?? .accentColor, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundStyle(snippet.trigger.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if snippet.mode == .immediate {
                        Image(systemName: "bolt.fill").imageScale(.small).foregroundStyle(.secondary)
                            .help("Expands immediately").accessibilityLabel("Expands immediately")
                    }
                    if TokenRenderer.containsTokens(snippet.expansion) {
                        Image(systemName: "curlybraces").imageScale(.small).foregroundStyle(.secondary)
                            .help("Contains tokens").accessibilityLabel("Contains tokens")
                    }
                    if hasProblem {
                        Image(systemName: "exclamationmark.triangle.fill").imageScale(.small).foregroundStyle(.orange)
                            .accessibilityLabel("Needs attention")
                    }
                }
                Text(snippet.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(isActive ? 1 : 0.45)

            Spacer(minLength: 8)

            if let group {
                Text(group.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(group.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(group.tint.opacity(0.14), in: Capsule())
            }
            Text(snippet.useCount.formatted())
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 28, alignment: .trailing)
                .help("Used \(snippet.useCount) times")

            Toggle("Turn \(snippet.trigger) on or off", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(snippet.isEnabled ? "Turn Off" : "Turn On")
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Settings page

/// Settings inside the main window, laid out like System Settings.
struct SettingsPage: View {
    @AppStorage("settingsPane") private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { pane }, set: { if let value = $0 { pane = value } })) {
                ForEach(SettingsPane.allCases) { item in
                    HStack(spacing: 9) {
                        SnippetIcon(symbol: item.symbol, color: item.color, size: 22)
                        Text(item.title)
                    }
                    .padding(.vertical, 2)
                    .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ScrollView {
                Group {
                    switch pane {
                    case .general: GeneralSettingsPane()
                    case .suggestions: SuggestionSettingsPane()
                    case .effects: EffectsSettingsPane()
                    case .shortcuts: ShortcutSettingsPane()
                    case .backup: BackupSettingsPane()
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .navigationTitle(pane.title)
        }
    }
}

// MARK: - Shared pieces

/// A snippet's icon in a small rounded square, tinted with its group's colour.
struct SnippetIcon: View {
    let symbol: String?
    let color: Color?
    var size: CGFloat = 24

    var body: some View {
        let fill = color ?? .accentColor
        Group {
            if let symbol, IconKind.isEmoji(symbol) {
                Text(symbol)
                    .font(.system(size: size * 0.58))
            } else {
                Image(systemName: symbol ?? "text.quote")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
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

enum SnippetDrag {
    static let prefix = "quill-snippet:"

    static func payload(for id: Snippet.ID) -> String { prefix + id.uuidString }

    static func snippetID(from payload: String) -> Snippet.ID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

/// Accepts dropped snippets (moves them into the group) and dropped text from other apps
/// (makes a new snippet there). Highlights while targeted.
private struct DropTarget<Content: View>: View {
    let groupID: SnippetGroup.ID?
    @ViewBuilder let content: Content
    @Environment(AppState.self) private var state
    @State private var isTargeted = false

    var body: some View {
        content
            .background(isTargeted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: String.self) { items, _ in
                state.handleDrop(items, into: groupID)
            } isTargeted: { isTargeted = $0 }
    }
}
