import SwiftUI
import UniformTypeIdentifiers

/// The main window: the quills sidebar on the left, always shown, and on the right the
/// page the floating tab bar picks: the selected quill's editor, Stats, History, the
/// Firing Range or Settings, with New among them.
struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @State private var searchText = ""
    @AppStorage("ungroupedExpanded") private var ungroupedExpanded = true
    @State private var groupName = ""

    private var store: SnippetStore { state.store }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func visible(_ snippets: [Snippet]) -> [Snippet] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? snippets : snippets.filter {
            $0.matches(query)
        }
        return state.sortOrder.sorted(matching)
    }

    var body: some View {
        @Bindable var state = state

        // The quills sidebar is always there; the tab bar picks what the right-hand side shows.
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 460)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch state.page {
                    case .snippets: detail
                    case .stats: OverviewView()
                    case .history: HistoryView()
                    case .firingRange: FiringRangeView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                MainTabBar()
                    .modifier(WindowCentred())
            }
            .background(Surface.page)
            .toolbarBackground(Surface.page, for: .windowToolbar)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        // Without a minimum, macOS can restore the window at a uselessly small size.
        .frame(minWidth: 1100, minHeight: 640)
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
        .sheet(item: $state.appearanceTarget) { target in
            IconColorEditor(target: target)
                .environment(state)
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
                Button("Keep Quills") { store.deleteGroup(id, keepingSnippets: true) }
                Button("Delete Group and Quills", role: .destructive) {
                    store.deleteGroup(id, keepingSnippets: false)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Keeping the quills moves them out of the group.")
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
                    .selectionDisabled()
            }

            if let update = state.updates.availableUpdate {
                UpdateBanner(release: update)
                    .listRowSeparator(.hidden)
            }


            // Collapsing is done with our own larger arrow, so sections are plain and rows are skipped when collapsed.
            if !loose.isEmpty || store.groups.isEmpty {
                Section {
                    if ungroupedExpanded || isSearching { rows(for: loose) }
                } header: {
                    DropHeader(groupID: nil) {
                        HStack(spacing: 8) {
                            Text(store.groups.isEmpty ? "Quills" : "Ungrouped")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            DisclosureArrow(isExpanded: $ungroupedExpanded)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) { ungroupedExpanded.toggle() }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(store.groups.isEmpty ? "Quills" : "Ungrouped")
                        .accessibilityValue(ungroupedExpanded ? "expanded" : "collapsed")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityAction(named: ungroupedExpanded ? "Collapse" : "Expand") { ungroupedExpanded.toggle() }
                    }
                }
                .collapsible(false)
            }

            ForEach(store.groups) { group in
                let snippets = visible(store.snippets(in: group.id))
                if !isSearching || !snippets.isEmpty {
                    Section {
                        if group.isExpanded || isSearching { rows(for: snippets) }
                    } header: {
                        DropHeader(groupID: group.id) {
                            GroupHeader(group: group, count: store.snippets(in: group.id).count)
                        }
                    }
                    .collapsible(false)
                }
            }
        }
        .listStyle(.sidebar)
        .modifier(DarkSidebar())
        // Double-clicking a snippet opens Icon and Colour. The menu stays empty so each row keeps its own.
        .contextMenu(forSelectionType: SidebarItem.self) { _ in
        } primaryAction: { items in
            if items.count == 1, let id = items.first?.snippetID {
                state.appearanceTarget = .snippet(id)
            }
        }
        .overlay {
            if store.snippets.isEmpty {
                ContentUnavailableView {
                    Label("No Quills", systemImage: "pencil.line")
                } description: {
                    Text("Create a quill, or bring in the text replacements you already use.")
                } actions: {
                    Button("New Quill") { state.newSnippet() }
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
                Button("New Quill", systemImage: "plus.circle") {
                    searchText = ""
                    state.newSnippet()
                }
                .help("New Quill (⌘N)")

                Button("New Group", systemImage: "folder.badge.plus") {
                    state.newGroup()
                }
                .help("New Group (⇧⌘N)")

                ToolbarDivider()

                Button("Add Starter Pack", systemImage: "shippingbox") {
                    state.isShowingPacks = true
                }
                .help("Add a Starter Pack")

                ToolbarDivider()

                Menu {
                    Button("New Quill", systemImage: "plus.circle") {
                        searchText = ""
                        state.newSnippet()
                    }
                    Button("New Group", systemImage: "folder.badge.plus") { state.newGroup() }
                    Divider()
                    Button("Add Starter Pack…", systemImage: "shippingbox") { state.isShowingPacks = true }
                    Button("Import Text Replacements…", systemImage: "square.and.arrow.down") { state.beginSystemImport() }
                    Button("Import Quills…", systemImage: "tray.and.arrow.down") { state.isShowingFileImporter = true }
                } label: {
                    // A fixed-size image: the toolbar would scale a symbol up to full size.
                    Image(nsImage: Self.smallChevron)
                        .accessibilityLabel("More Ways to Add Quills")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More Ways to Add Quills")
            }
        }
    }

    /// The small dropdown arrow, like the one on a split button.
    private static let smallChevron: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "More")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    @ViewBuilder
    private func rows(for snippets: [Snippet]) -> some View {
        ForEach(snippets) { snippet in
            SnippetRow(
                snippet: snippet,
                group: store.group(for: snippet),
                tint: store.tint(for: snippet),
                isEnabled: store.enabledBinding(for: snippet.id),
                hasProblem: store.problem(with: snippet) != nil
            )
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .tag(SidebarItem.snippet(snippet.id))
            .draggable(SnippetDrag.payload(for: dragIDs(for: snippet))) {
                let count = dragIDs(for: snippet).count
                Label(count > 1 ? "\(count) Quills" : (snippet.trigger.isEmpty ? "Quill" : snippet.trigger), systemImage: "text.quote")
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .modifier(SnippetRowDrop(snippet: snippet))
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
                Label("\(ids.count) Quills Selected", systemImage: "square.stack")
            } description: {
                Text("Turn them on or off, move them to a group, or right-click for more.")
            } actions: {
                let allOn = ids.compactMap(store.snippet).allSatisfy(\.isEnabled)
                Button(allOn ? "Turn Off" : "Turn On") {
                    for id in ids { store.setEnabled(id, !allOn) }
                }
                Menu("Move to Group") {
                    Button("No Group") { store.move(ids, to: nil) }
                    if !store.groups.isEmpty { Divider() }
                    ForEach(store.groups) { group in
                        Button(group.name) { store.move(ids, to: group.id) }
                    }
                }
                .fixedSize()
                Button("Delete \(ids.count) Quills", role: .destructive) {
                    delete(ids)
                }
            }
        } else {
            ContentUnavailableView("Select a Quill", systemImage: "pencil.line",
                                   description: Text("Choose a quill in the sidebar to edit it."))
        }
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

    // MARK: Actions

    /// Dragging a selected row drags the whole selection, in library order, like Finder.
    private func dragIDs(for snippet: Snippet) -> [Snippet.ID] {
        let selected = state.selectedSnippetIDs
        guard selected.contains(snippet.id), selected.count > 1 else { return [snippet.id] }
        return store.snippets.map(\.id).filter(selected.contains)
    }

    /// Right-clicking a selected row acts on the whole selection, like Finder.
    private func contextIDs(for snippet: Snippet) -> Set<Snippet.ID> {
        let selected = state.selectedSnippetIDs
        return selected.contains(snippet.id) ? selected : [snippet.id]
    }

    private func delete(_ ids: Set<Snippet.ID>) {
        store.delete(ids, undoManager: undoManager)
        state.selection.subtract(ids.map { .snippet($0) })
    }
}

// MARK: - Rows

/// The small round symbols on a group header (add, options): one size, weight and colour.
private struct HeaderSymbol: View {
    let name: String

    var body: some View {
        // A borderless menu draws its symbol at the standard 13-point size in the label colour,
        // so the add button uses exactly that too.
        Image(systemName: name)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(width: 26, height: 24)
            .contentShape(Rectangle())
    }
}

/// The main window's floating tab bar, like the one on iPhone: a symbol over a label
/// for each page, the current one in the accent colour, and New as a filled circle in the middle.
private struct MainTabBar: View {
    @Environment(AppState.self) private var state

    private struct Tab: Identifiable {
        let page: AppPage
        let symbol: String
        var id: AppPage { page }
    }

    private let leading = [Tab(page: .snippets, symbol: "rectangle.stack.fill"), Tab(page: .stats, symbol: "chart.bar.fill"),
                           Tab(page: .history, symbol: "clock.fill")]
    private let trailing = [Tab(page: .firingRange, symbol: "scope"), Tab(page: .settings, symbol: "gearshape.fill")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(leading) { tab($0) }
            newButton
            ForEach(trailing) { tab($0) }
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 34)
                .padding(.horizontal, 4)
            Button {
                NSApp.terminate(nil)
            } label: {
                TabLabel(symbol: "power", title: "Quit")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Quit Quill")
            .accessibilityLabel("Quit Quill")
            .accessibilityIdentifier("tab-quit")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Surface.bar, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .padding(.top, 8)
        .padding(.bottom, 12)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }

    private func tab(_ tab: Tab) -> some View {
        let isSelected = state.page == tab.page
        return Button {
            state.page = tab.page
        } label: {
            TabLabel(symbol: tab.symbol, title: tab.page.title)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(tab.page.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("tab-\(tab.page.rawValue)")
    }

    private var newButton: some View {
        Button {
            state.page = .snippets
            state.newSnippet()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: Circle())
                Text("New")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("New Quill (⌘N)")
        .accessibilityLabel("New Quill")
        .accessibilityIdentifier("tab-new")
    }
}

/// In dark mode the sidebar gets Quill's darker, solid surface; light mode keeps the system sidebar.
private struct DarkSidebar: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .scrollContentBackground(.hidden)
                .background(Surface.sidebar)
        } else {
            content
        }
    }
}

/// Centres a view on the whole window rather than its column, sliding it back only as far
/// as needed to stay clear of the sidebar when the window is narrow.
private struct WindowCentred: ViewModifier {
    @State private var column = CGRect.zero
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .offset(x: shift)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { column = $0 }
    }

    /// The column runs to the window's right edge, so the window's centre is half its maxX.
    private var shift: CGFloat {
        guard column.width > 0, width > 0 else { return 0 }
        let toWindowCentre = column.maxX / 2 - column.midX
        let clearOfSidebar = column.minX + 12 + width / 2 - column.midX
        return min(0, max(toWindowCentre, clearOfSidebar))
    }
}

/// A symbol over a short label, the shape of every tab in Quill's tab bars.
struct TabLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .frame(width: 92, height: 52)
        .contentShape(Rectangle())
    }
}

/// A thin vertical line between groups of toolbar buttons.
private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

private struct GroupHeader: View {
    let group: SnippetGroup
    let count: Int
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            Button {
                state.appearanceTarget = .group(group.id)
            } label: {
                SnippetIcon(symbol: group.symbol, color: group.tint, size: 24)
            }
            .buttonStyle(.plain)
            .help("Change Icon and Colour")

            // Only the name and the empty space after it collapse the group: the icon, menu,
            // switch and arrow each keep to their own job.
            HStack(spacing: 0) {
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // Double-click edits the group's icon and colour; a single click collapses or expands it.
            .gesture(
                TapGesture(count: 2).onEnded { state.appearanceTarget = .group(group.id) }
                    .exclusively(before: TapGesture().onEnded {
                        withAnimation(.snappy(duration: 0.2)) {
                            state.store.updateGroup(group.id) { $0.isExpanded.toggle() }
                        }
                    })
            )
            .help(group.isExpanded ? "Click to collapse \(group.name). Double-click to change its icon and colour. Drag to reorder."
                                   : "Click to expand \(group.name). Double-click to change its icon and colour. Drag to reorder.")
            // Dragging the group's name reorders groups.
            .draggable(SnippetDrag.groupPayload(for: group.id)) {
                Label(group.name, systemImage: IconKind.isEmoji(group.symbol) ? "folder.fill" : group.symbol)
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            Button {
                state.newSnippet(in: group.id)
            } label: {
                HeaderSymbol(name: "plus.circle")
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("New Quill in \(group.name)")
            .accessibilityLabel("New quill in \(group.name)")

            Menu {
                GroupActionsMenu(group: group)
            } label: {
                HeaderSymbol(name: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Group Options")
            .accessibilityLabel("Options for \(group.name)")

            Toggle("Turn \(group.name) on or off", isOn: state.store.groupEnabledBinding(for: group.id))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(group.isEnabled ? "Turn Group Off" : "Turn Group On")

            DisclosureArrow(isExpanded: state.store.groupExpandedBinding(for: group.id))
        }
        .padding(.vertical, 3)
        .opacity(group.isEnabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .contextMenu {
            GroupActionsMenu(group: group)
        }
        // macOS reads a sidebar section header as one element, so its controls are offered as named actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name) group")
        .accessibilityValue("\(count) \(count == 1 ? "quill" : "quills"), \(group.isEnabled ? "on" : "off"), \(group.isExpanded ? "expanded" : "collapsed")")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("group-header-\(group.name)")
        .accessibilityAction(named: group.isExpanded ? "Collapse" : "Expand") {
            state.store.updateGroup(group.id) { $0.isExpanded.toggle() }
        }
        .accessibilityAction(named: group.isEnabled ? "Turn Off" : "Turn On") {
            state.store.updateGroup(group.id) { $0.isEnabled.toggle() }
        }
        .accessibilityAction(named: "New Quill") { state.newSnippet(in: group.id) }
        .accessibilityAction(named: "Rename") { state.renamingGroupID = group.id }
        .accessibilityAction(named: "Change Colour") { state.colorPickerGroupID = group.id }
    }
}

/// A large, easy-to-hit arrow that collapses and expands a sidebar section.
private struct DisclosureArrow: View {
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse" : "Expand")
        .accessibilityLabel(isExpanded ? "Collapse group" : "Expand group")
    }
}

/// Overview and History rows at the top of the sidebar.
private struct SidebarLink: View {
    let title: String
    let symbol: String
    let color: Color
    var badge: String?

    var body: some View {
        HStack(spacing: 10) {
            SnippetIcon(symbol: symbol, color: color, size: 26)
            Text(title).font(.body.weight(.medium))
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let group: SnippetGroup?
    let tint: Color
    @Environment(AppState.self) private var state
    @Binding var isEnabled: Bool
    let hasProblem: Bool

    private var isActive: Bool { snippet.isEnabled && (group?.isEnabled ?? true) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                state.appearanceTarget = .snippet(snippet.id)
            } label: {
                SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: tint, size: 30)
            }
            .buttonStyle(.plain)
            .help("Change Icon and Colour")
            .accessibilityLabel("Icon and colour for \(snippet.trigger)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(snippet.trigger.isEmpty ? "New Quill" : snippet.trigger)
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
                    .fill(fill)
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

                Text("\(count) \(count == 1 ? "quill" : "quills")")
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Quill Is Off")
                    .font(.headline)
                Text("Allow Accessibility access so Quill can expand your quills.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Allow Access…") {
                    state.requestAccess()
                    state.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Drag and drop

/// What a drag carries inside Quill: one or more snippets, or a group.
enum SnippetDrag {
    static let prefix = "quill-snippet:"
    static let groupPrefix = "quill-group:"

    static func payload(for id: Snippet.ID) -> String { prefix + id.uuidString }

    static func payload(for ids: [Snippet.ID]) -> String { prefix + ids.map(\.uuidString).joined(separator: ",") }

    static func groupPayload(for id: SnippetGroup.ID) -> String { groupPrefix + id.uuidString }

    static func snippetIDs(from payload: String) -> [Snippet.ID] {
        guard payload.hasPrefix(prefix) else { return [] }
        return payload.dropFirst(prefix.count).split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    static func snippetID(from payload: String) -> Snippet.ID? { snippetIDs(from: payload).first }

    static func groupID(from payload: String) -> SnippetGroup.ID? {
        guard payload.hasPrefix(groupPrefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(groupPrefix.count)))
    }

    static func isQuillPayload(_ payload: String) -> Bool {
        payload.hasPrefix(prefix) || payload.hasPrefix(groupPrefix)
    }
}

/// A snippet row as a drop target: snippets dropped on it move to just above it, in its group.
/// A line above the row shows where they'll go.
private struct SnippetRowDrop: ViewModifier {
    let snippet: Snippet
    @Environment(AppState.self) private var state
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isTargeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 3)
                        .offset(y: -3)
                        .transition(.opacity)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                let ids = items.flatMap(SnippetDrag.snippetIDs(from:))
                if !ids.isEmpty {
                    withAnimation(.snappy(duration: 0.25)) {
                        state.store.move(Set(ids), before: snippet.id, in: snippet.groupID)
                        state.sortOrder = .manual
                    }
                    return true
                }
                // Text from another app becomes a new snippet in this snippet's group.
                guard items.allSatisfy({ !SnippetDrag.isQuillPayload($0) }) else { return false }
                return state.handleDrop(items, into: snippet.groupID)
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
            }
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
                // A group dropped on another group's header moves just above it.
                if let dragged = items.lazy.compactMap(SnippetDrag.groupID(from:)).first {
                    guard let groupID, dragged != groupID else { return false }
                    withAnimation(.snappy(duration: 0.25)) { state.store.moveGroup(dragged, before: groupID) }
                    return true
                }
                // Snippets dropped on a header go to the end of that group.
                let ids = items.flatMap(SnippetDrag.snippetIDs(from:))
                if !ids.isEmpty {
                    withAnimation(.snappy(duration: 0.25)) {
                        state.store.move(Set(ids), before: nil, in: groupID)
                        if let groupID { state.store.updateGroup(groupID) { $0.isExpanded = true } }
                    }
                    return true
                }
                return state.handleDrop(items, into: groupID)
            } isTargeted: { isTargeted = $0 }
    }
}
