import SwiftUI
import UniformTypeIdentifiers

/// The main window: Overview and snippets (loose and in groups) in the sidebar,
/// the dashboard or the selected snippet's editor beside them.
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
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.expansion.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted(by: state.sortOrder.areInIncreasingOrder)
    }

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 460)
        } detail: {
            detail
        }
        // Without a minimum, macOS can restore the window at a uselessly small size.
        .frame(minWidth: 900, minHeight: 600)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
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
                    .selectionDisabled()
            }

            if let update = state.updates.availableUpdate {
                UpdateBanner(release: update)
                    .listRowSeparator(.hidden)
            }

            if !isSearching {
                SidebarLink(title: "Stats", symbol: "chart.bar.xaxis", color: .purple)
                    .tag(SidebarItem.overview)
                SidebarLink(title: "History", symbol: "clock.arrow.circlepath", color: .teal,
                            badge: state.history.entries.isEmpty ? nil : "\(state.history.entries.count)")
                    .tag(SidebarItem.history)
            }

            // Collapsing is done with our own larger arrow, so sections are plain and rows are skipped when collapsed.
            if !loose.isEmpty || store.groups.isEmpty {
                Section {
                    if ungroupedExpanded || isSearching { rows(for: loose) }
                } header: {
                    DropHeader(groupID: nil) {
                        HStack(spacing: 8) {
                            Text(store.groups.isEmpty ? "Snippets" : "Ungrouped")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            DisclosureArrow(isExpanded: $ungroupedExpanded)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) { ungroupedExpanded.toggle() }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(store.groups.isEmpty ? "Snippets" : "Ungrouped")
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
                Button("New Snippet", systemImage: "plus.circle.fill") {
                    searchText = ""
                    state.newSnippet()
                }
                .help("New Snippet (⌘N)")

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
                    Button("New Snippet", systemImage: "plus.circle") {
                        searchText = ""
                        state.newSnippet()
                    }
                    Button("New Group", systemImage: "folder.badge.plus") { state.newGroup() }
                    Divider()
                    Button("Add Starter Pack…", systemImage: "shippingbox") { state.isShowingPacks = true }
                    Button("Import Text Replacements…", systemImage: "square.and.arrow.down") { state.beginSystemImport() }
                    Button("Import Snippets…", systemImage: "tray.and.arrow.down") { state.isShowingFileImporter = true }
                } label: {
                    // A fixed-size image: the toolbar would scale a symbol up to full size.
                    Image(nsImage: Self.smallChevron)
                        .accessibilityLabel("More Ways to Add Snippets")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More Ways to Add Snippets")
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
                Button("Delete \(ids.count) Snippets", role: .destructive) {
                    delete(ids)
                }
            }
        } else if state.selection == [.history] {
            HistoryView()
        } else {
            OverviewView()
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
            .onTapGesture {
                withAnimation(.snappy(duration: 0.2)) {
                    state.store.updateGroup(group.id) { $0.isExpanded.toggle() }
                }
            }
            .help(group.isExpanded ? "Click to collapse \(group.name)" : "Click to expand \(group.name)")

            Menu {
                GroupActionsMenu(group: group)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
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
        .accessibilityValue("\(count) \(count == 1 ? "snippet" : "snippets"), \(group.isEnabled ? "on" : "off"), \(group.isExpanded ? "expanded" : "collapsed")")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("group-header-\(group.name)")
        .accessibilityAction(named: group.isExpanded ? "Collapse" : "Expand") {
            state.store.updateGroup(group.id) { $0.isExpanded.toggle() }
        }
        .accessibilityAction(named: group.isEnabled ? "Turn Off" : "Turn On") {
            state.store.updateGroup(group.id) { $0.isEnabled.toggle() }
        }
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Quill Is Off")
                    .font(.headline)
                Text("Allow Accessibility access so Quill can expand your snippets.")
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
