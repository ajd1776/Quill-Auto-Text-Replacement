import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Edits one snippet in the inspector, in sections like Get Info: the shortcut at the top,
/// then Text, Behaviour, Organise, Apps and Usage. Changes save as you type.
struct SnippetDetailView: View {
    @Binding var snippet: Snippet
    let onDelete: () -> Void

    @Environment(AppState.self) private var state
    @FocusState private var isTriggerFocused: Bool
    @State private var editor = TokenEditorController()
    @State private var isPickingIcon = false
    @State private var previewID = 0

    private var group: SnippetGroup? { state.store.group(for: snippet) }
    private var tint: Color { group?.tint ?? .accentColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                textSection
                behaviourSection
                organiseSection
                appsSection
                usageSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.automatic)
        .navigationTitle(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
        .onAppear {
            if snippet.trigger.isEmpty { isTriggerFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    isPickingIcon = true
                } label: {
                    SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: tint, size: 54)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.white, tint)
                                .offset(x: 4, y: 4)
                        }
                }
                .buttonStyle(.plain)
                .help("Change Icon")
                .accessibilityLabel("Change icon")
                .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
                    IconPicker(current: snippet.symbol, tint: tint, defaultTitle: "Use Group Icon") { snippet.symbol = $0 }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcut")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Shortcut", text: $snippet.trigger, prompt: Text("Type a shortcut"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .focused($isTriggerFocused)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Shortcut")
                        .accessibilityIdentifier("shortcut-field")
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("Snippet on", isOn: $snippet.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(snippet.isEnabled ? "Turn Off" : "Turn On")
                        .accessibilityLabel("Snippet on")
                    actionsMenu
                }
            }
            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let problem = state.store.problem(with: snippet) {
            StatusPill(text: problem, symbol: "exclamationmark.triangle.fill", color: .orange)
        } else if !state.store.isActive(snippet) {
            StatusPill(text: snippet.isEnabled ? "Group \u{201C}\(group?.name ?? "")\u{201D} is off" : "Off",
                       symbol: "pause.circle.fill", color: .secondary)
        } else {
            StatusPill(text: "Ready · " + (snippet.mode == .immediate ? "expands as you type it" : "expands after a space"),
                       symbol: "checkmark.circle.fill", color: .green)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Insert Now", systemImage: "text.insert") {
                state.insert(snippet, after: 0.35)
                NSApp.hide(nil)
            }
            .disabled(snippet.expansion.isEmpty)
            Button("Copy Text", systemImage: "doc.on.doc") { state.copyExpansion(snippet.id) }
                .disabled(snippet.expansion.isEmpty)
            Button("Duplicate", systemImage: "plus.square.on.square") {
                state.selection = [.snippet(snippet.id)]
                state.duplicateSelection()
            }
            Divider()
            Button("Delete Snippet", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More Actions")
        .accessibilityLabel("More actions")
        .accessibilityIdentifier("snippet-actions")
    }

    // MARK: Text

    private var textSection: some View {
        InspectorSection("Text", symbol: "text.alignleft") {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TokenTextEditor(text: $snippet.expansion, controller: editor, fontSize: 14,
                                    inset: NSSize(width: 8, height: 10))
                        .accessibilityIdentifier("expansion-editor")
                    if snippet.expansion.isEmpty {
                        Text("Type the text this shortcut expands to…")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 120, idealHeight: editorHeight, maxHeight: 260)

                Divider()

                HStack(spacing: 10) {
                    tokenMenu
                    Spacer()
                    Text(countText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))

            if TokenRenderer.containsTokens(snippet.expansion) {
                tokenPreview
            }
        }
    }

    /// Grows with the text up to a point, then scrolls.
    private var editorHeight: CGFloat {
        let lines = snippet.expansion.split(separator: "\n", omittingEmptySubsequences: false).count
        return min(260, max(120, CGFloat(lines) * 20 + 30))
    }

    private var tokenMenu: some View {
        Menu {
            ForEach(SnippetToken.allCases) { token in
                Button {
                    editor.insert(token.placeholder)
                } label: {
                    Label("\(token.title)  \(token.placeholder)", systemImage: token.symbol)
                }
            }
            Divider()
            Button {
                editor.insert(FillInToken.placeholder("Name"), selecting: "Name")
            } label: {
                Label("\(FillInToken.title)  {input:…}", systemImage: FillInToken.symbol)
            }
        } label: {
            Label("Insert Token", systemImage: "curlybraces")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Insert a date, time, clipboard, cursor or fill-in placeholder")
    }

    private var countText: String {
        let characters = snippet.expansion.count
        let lines = snippet.expansion.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(characters) \(characters == 1 ? "character" : "characters") · \(lines) \(lines == 1 ? "line" : "lines")"
    }

    private var tokenPreview: some View {
        let fields = TokenRenderer.inputFields(in: snippet.expansion)
        let rendered = TokenRenderer.render(snippet.expansion, clipboard: NSPasteboard.general.string(forType: .string) ?? "")
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Preview", systemImage: "eye")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !fields.isEmpty {
                    Label(fields.count == 1 ? "Asks for 1 value" : "Asks for \(fields.count) values", systemImage: "rectangle.and.pencil.and.ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(previewString(rendered))
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Shows where {cursor} will leave the cursor with a bar.
    private func previewString(_ rendered: RenderedText) -> String {
        guard let back = rendered.cursorBack, back <= rendered.text.count else { return rendered.text }
        var text = rendered.text
        text.insert("|", at: text.index(text.endIndex, offsetBy: -back))
        return text
    }

    // MARK: Behaviour

    private var behaviourSection: some View {
        InspectorSection("Behaviour", symbol: "keyboard") {
            InspectorCard {
                InspectorRow("Expands") {
                    Picker("Expands", selection: $snippet.mode) {
                        Text("After Space").tag(ExpansionMode.afterDelimiter)
                        Text("Immediately").tag(ExpansionMode.immediate)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("mode-picker")
                } detail: {
                    Text(snippet.mode.explanation)
                }

                Divider()

                InspectorRow("Capitals") {
                    Toggle("Match any capitals", isOn: $snippet.matchesAnyCase)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                } detail: {
                    Text(capitalsDetail)
                }

                Divider()

                InspectorRow("Effect") {
                    HStack(spacing: 6) {
                        // Spelled out because Binding has its own animation(_:) method.
                        Picker("Effect", selection: Binding(get: { snippet.animation }, set: { snippet.animation = $0; previewID += 1 })) {
                            Text("Default (\(state.defaultAnimation.title))").tag(ReplacementAnimation?.none)
                            Divider()
                            ForEach(ReplacementAnimation.allCases) { style in
                                Label(style.title, systemImage: style.symbol).tag(Optional(style))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("effect-picker")
                    }
                } detail: {
                    Text((snippet.animation ?? state.defaultAnimation).explanation)
                }

                AnimationPreview(style: snippet.animation ?? state.defaultAnimation, speed: state.typewriterSpeed,
                                 trigger: snippet.trigger.isEmpty ? "eml" : snippet.trigger,
                                 expansion: previewExpansion, reduceMotion: state.shouldReduceMotion, height: 96, prefix: "")
                    .id(previewID)
            }
        }
    }

    private var capitalsDetail: String {
        let trigger = snippet.trigger.isEmpty ? "eml" : snippet.trigger
        return snippet.matchesAnyCase
            ? "\(trigger.uppercased()) types ALL CAPS, \(trigger.prefix(1).uppercased() + trigger.dropFirst()) starts with a capital."
            : "Only \(trigger) expands, exactly as written."
    }

    private var previewExpansion: String {
        let flat = TokenRenderer.render(snippet.expansion, clipboard: "").text.replacingOccurrences(of: "\n", with: " ")
        guard !flat.isEmpty else { return "name@example.com" }
        return flat.count > 34 ? String(flat.prefix(33)) + "…" : flat
    }

    // MARK: Organise

    private var organiseSection: some View {
        InspectorSection("Organise", symbol: "folder") {
            InspectorCard {
                InspectorRow("Group") {
                    Picker("Group", selection: $snippet.groupID) {
                        Text("No Group").tag(SnippetGroup.ID?.none)
                        if !state.store.groups.isEmpty { Divider() }
                        ForEach(state.store.groups) { group in
                            Label(group.name, systemImage: IconKind.isEmoji(group.symbol) ? "folder.fill" : group.symbol)
                                .tag(Optional(group.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("group-picker")
                }

                Divider()

                InspectorRow("Icon") {
                    HStack(spacing: 8) {
                        SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: tint, size: 22)
                        Button("Choose…") { isPickingIcon = true }
                        if snippet.symbol != nil {
                            Button("Use Group Icon") { snippet.symbol = nil }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
        }
    }

    // MARK: Apps

    private var appsSection: some View {
        InspectorSection("Apps", symbol: "macwindow") {
            InspectorCard {
                InspectorRow("Works In") {
                    Picker("Works in", selection: Binding(
                        get: { !snippet.appBundleIDs.isEmpty },
                        set: { limited in
                            if !limited { snippet.appBundleIDs = [] } else if snippet.appBundleIDs.isEmpty { chooseApp() }
                        }
                    )) {
                        Text("All Apps").tag(false)
                        Text("Only Some").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("apps-picker")
                } detail: {
                    Text(snippet.appBundleIDs.isEmpty ? "Expands in every app you type in." : "Expands only in the apps below.")
                }

                if !snippet.appBundleIDs.isEmpty {
                    Divider()
                    FlowLayout(spacing: 6) {
                        ForEach(snippet.appBundleIDs, id: \.self) { bundleID in
                            AppChip(bundleID: bundleID) {
                                snippet.appBundleIDs.removeAll { $0 == bundleID }
                            }
                        }
                        addAppMenu
                    }
                }
            }
        }
    }

    private var addAppMenu: some View {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap(\.bundleIdentifier)
            .filter { !snippet.appBundleIDs.contains($0) }
            .reduce(into: [String]()) { list, id in if !list.contains(id) { list.append(id) } }
            .sorted { AppInfo.name(for: $0).localizedStandardCompare(AppInfo.name(for: $1)) == .orderedAscending }

        return Menu {
            if !running.isEmpty {
                Section("Open Apps") {
                    ForEach(running, id: \.self) { bundleID in
                        Button(AppInfo.name(for: bundleID)) { snippet.appBundleIDs.append(bundleID) }
                    }
                }
                Divider()
            }
            Button("Choose App…", action: chooseApp)
        } label: {
            Label("Add App", systemImage: "plus")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Use in These Apps"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !snippet.appBundleIDs.contains(id) {
                snippet.appBundleIDs.append(id)
            }
        }
    }

    // MARK: Usage

    private var usageSection: some View {
        let days = QuillStats.days(14, for: snippet.id, in: state.history.entries)
        return InspectorSection("Usage", symbol: "chart.bar") {
            InspectorCard {
                HStack(spacing: 0) {
                    UsageFigure(value: snippet.useCount.formatted(), label: snippet.useCount == 1 ? "use" : "uses")
                    Divider().frame(height: 34)
                    UsageFigure(value: snippet.keysSaved.formatted(), label: "keys saved")
                    Divider().frame(height: 34)
                    UsageFigure(value: lastUsedShort, label: "last used")
                }

                if days.contains(where: { $0.uses > 0 }) {
                    Chart(days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Uses", day.uses), width: .ratio(0.6))
                            .foregroundStyle(tint)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 64)
                    .accessibilityLabel("Uses per day for the last 14 days")
                }

                Text("Created \(snippet.created.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var lastUsedShort: String {
        guard let lastUsed = snippet.lastUsed else { return "Never" }
        return lastUsed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

// MARK: - Inspector pieces

/// A titled group in the inspector.
struct InspectorSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// The rounded box rows sit in, like a grouped form.
struct InspectorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A label on the left, a control on the right, and an optional line of help below.
struct InspectorRow<Control: View, Detail: View>: View {
    let title: String
    @ViewBuilder let control: Control
    @ViewBuilder let detail: Detail

    init(_ title: String, @ViewBuilder control: () -> Control, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.control = control()
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                control
            }
            detail
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension InspectorRow where Detail == EmptyView {
    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.init(title, control: control) { EmptyView() }
    }
}

private struct UsageFigure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct AppChip: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(AppInfo.name(for: bundleID))
                .font(.callout)
                .lineLimit(1)
            Button("Remove \(AppInfo.name(for: bundleID))", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Small coloured capsule for the snippet's status.
private struct StatusPill: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

/// App names from bundle identifiers.
enum AppInfo {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
