import SwiftUI
import UniformTypeIdentifiers

/// Edits one snippet, Notes-style: the shortcut as a title, the text below it with tokens as
/// chips, and the snippet's settings at the bottom. Changes save as you type.
struct SnippetDetailView: View {
    @Binding var snippet: Snippet
    let onDelete: () -> Void

    @Environment(AppState.self) private var state
    @FocusState private var isTriggerFocused: Bool
    @State private var editor = TokenEditorController()

    private let inset: CGFloat = 28
    private let editorFontSize: CGFloat = 15

    private var group: SnippetGroup? { state.store.group(for: snippet) }
    private var tint: Color { state.store.tint(for: snippet) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, inset)
            editorArea
            if TokenRenderer.containsTokens(snippet.expansion) {
                tokenPreview
            }
            Divider()
            footer
        }
        .background(Surface.editor)
        .navigationTitle(snippet.trigger.isEmpty ? "New Quill" : snippet.trigger)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Text", systemImage: "doc.on.doc") {
                    state.copyExpansion(snippet.id)
                }
                .help("Copy Text")
                .disabled(snippet.expansion.isEmpty)

                Button("Delete Quill", systemImage: "trash", action: onDelete)
                    .help("Delete Quill")
            }
        }
        .onAppear {
            if snippet.trigger.isEmpty { isTriggerFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        let problem = state.store.problem(with: snippet)

        return HStack(alignment: .center, spacing: 16) {
            Button {
                state.appearanceTarget = .snippet(snippet.id)
            } label: {
                SnippetIcon(symbol: snippet.symbol ?? group?.symbol, color: tint, size: 52)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, tint)
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(.plain)
            .help("Change Icon and Colour")
            .accessibilityLabel("Change icon and colour")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    StatusDot(isOn: state.store.isActive(snippet), help: statusHelp)
                    TextField("Shortcut", text: $snippet.trigger, prompt: Text("Shortcut"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .focused($isTriggerFocused)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Shortcut")
                }

                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                notesField
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Toggle("Quill on", isOn: $snippet.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(snippet.isEnabled ? "Turn Off" : "Turn On")
                .accessibilityLabel("Quill on")
        }
        .padding(.horizontal, inset)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var statusHelp: String {
        if state.store.isActive(snippet) { return "On: this quill expands" }
        if snippet.isEnabled { return "Off: group \u{201C}\(group?.name ?? "")\u{201D} is off" }
        return "Off"
    }

    // MARK: Editor

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            TokenTextEditor(text: $snippet.expansion, controller: editor, fontSize: editorFontSize,
                            inset: NSSize(width: inset - 5, height: 14))

            if snippet.expansion.isEmpty {
                Text("Type the text this shortcut expands to…")
                    .font(.system(size: editorFontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, inset)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 14) {
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
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Insert a date, time, clipboard, cursor or fill-in placeholder")

                Spacer()

                Text(countText + " · " + usageText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(lastUsedText)
            }
            .padding(.horizontal, inset)
            .padding(.bottom, 8)
        }
    }

    private var countText: String {
        let characters = snippet.expansion.count
        let lines = snippet.expansion.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(characters) \(characters == 1 ? "character" : "characters") · \(lines) \(lines == 1 ? "line" : "lines")"
    }

    private var tokenPreview: some View {
        let fields = TokenRenderer.inputFields(in: snippet.expansion)
        let rendered = TokenRenderer.render(snippet.expansion, clipboard: NSPasteboard.general.string(forType: .string) ?? "")
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label("Preview", systemImage: "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(previewString(rendered))
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if !fields.isEmpty {
                Text(fields.count == 1 ? "Asks for 1 value" : "Asks for \(fields.count) values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 10)
        .background(tint.opacity(0.07))
    }

    /// Shows where {cursor} will leave the cursor with a bar.
    private func previewString(_ rendered: RenderedText) -> String {
        guard let back = rendered.cursorBack, back <= rendered.text.count else { return rendered.text }
        var text = rendered.text
        text.insert("|", at: text.index(text.endIndex, offsetBy: -back))
        return text
    }

    // MARK: Footer

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            optionPills
            ScrollView(.horizontal, showsIndicators: false) { optionPills }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// The quill's options as one row of coloured pills, each a menu.
    private var optionPills: some View {
        HStack(alignment: .bottom, spacing: 6) {
            OptionPill(title: group?.name ?? "No Group", symbol: "folder.fill", color: .purple, help: "The group this quill belongs to") {
                Picker("Group", selection: $snippet.groupID) {
                    Text("No Group").tag(SnippetGroup.ID?.none)
                    if !state.store.groups.isEmpty { Divider() }
                    ForEach(state.store.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
            }
            .pillCaption("Group")

            OptionPill(title: snippet.mode.title, symbol: "keyboard.fill", color: .blue, help: "When the shortcut expands as you type") {
                Picker("Expands", selection: $snippet.mode) {
                    ForEach(ExpansionMode.allCases) { Text($0.title).tag($0) }
                }
            }
            .pillCaption("Expands")

            OptionPill(title: snippet.animation?.title ?? "Default (\(state.defaultAnimationsTitle))",
                       symbol: "sparkles", color: .orange, help: "The effect that plays when it expands") {
                // Spelled out because Binding has its own animation(_:) method.
                Picker("Effect", selection: Binding(get: { snippet.animation }, set: { snippet.animation = $0 })) {
                    Text("Default (\(state.defaultAnimationsTitle))").tag(ReplacementAnimation?.none)
                    Divider()
                    ForEach(ReplacementAnimation.allCases) { style in
                        Label(style.title, systemImage: style.symbol).tag(Optional(style))
                    }
                }
            }
            .pillCaption("Effect")

            appsMenu
                .pillCaption("Works in")

            Button {
                snippet.matchesAnyCase.toggle()
            } label: {
                PillLabel(title: capitalsTitle,
                          symbol: snippet.matchesAnyCase ? "checkmark.circle.fill" : "circle",
                          color: snippet.matchesAnyCase ? .green : .gray, showsChevron: false)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(snippet.matchesAnyCase
                  ? "On: the shortcut expands however you capitalise it, and the text follows your capitals. Click to only expand when typed exactly."
                  : "Off: the shortcut only expands when typed exactly as written. Click to expand in any capitals.")
            .accessibilityLabel("Match any capitals")
            .accessibilityValue(snippet.matchesAnyCase ? "On" : "Off")
            .accessibilityAddTraits(snippet.matchesAnyCase ? [.isSelected, .isButton] : .isButton)
            .pillCaption("Match capitals")
        }
        .fixedSize()
    }

    /// Explains the capitals setting with this quill's own shortcut, such as "Any: ead, EAD".
    private var capitalsTitle: String {
        let trigger = snippet.trigger
        let lower = trigger.lowercased(), upper = trigger.uppercased()
        guard !trigger.isEmpty, trigger.count <= 10, lower != upper else {
            return snippet.matchesAnyCase ? "Any capitals" : "Exactly as typed"
        }
        if snippet.matchesAnyCase {
            let other = trigger == lower ? upper : lower
            return "Any: \(trigger), \(other)…"
        }
        return "Only \(trigger) exactly"
    }

    // MARK: Notes

    /// Your own notes about the quill, under its title. Never typed; searches match them.
    private var notesField: some View {
        TextField("Notes", text: $snippet.notes, prompt: Text("Add notes: what it's for, where you use it"), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Notes")
            .accessibilityIdentifier("quill-notes")
            .help("Notes are just for you. They're never typed, and searches match them.")
    }

    // MARK: Apps

    private var appsTitle: String {
        switch snippet.appBundleIDs.count {
        case 0: "All Apps"
        case 1: AppInfo.name(for: snippet.appBundleIDs[0])
        default: "\(snippet.appBundleIDs.count) Apps"
        }
    }

    private var appsMenu: some View {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap(\.bundleIdentifier)
        let candidates = (snippet.appBundleIDs + running)
            .reduce(into: [String]()) { list, id in if !list.contains(id) { list.append(id) } }
            .sorted { AppInfo.name(for: $0).localizedStandardCompare(AppInfo.name(for: $1)) == .orderedAscending }

        return Menu {
            Toggle("All Apps", isOn: Binding(
                get: { snippet.appBundleIDs.isEmpty },
                set: { if $0 { snippet.appBundleIDs = [] } }
            ))
            Divider()
            Section("Only In") {
                ForEach(candidates, id: \.self) { bundleID in
                    Toggle(AppInfo.name(for: bundleID), isOn: Binding(
                        get: { snippet.appBundleIDs.contains(bundleID) },
                        set: { isOn in
                            if isOn {
                                snippet.appBundleIDs.append(bundleID)
                            } else {
                                snippet.appBundleIDs.removeAll { $0 == bundleID }
                            }
                        }
                    ))
                }
            }
            Divider()
            Button("Choose App…", action: chooseApp)
        } label: {
            PillLabel(title: appsTitle, symbol: snippet.appBundleIDs.isEmpty ? "macwindow.on.rectangle" : "app.badge.checkmark",
                      color: .yellow)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .help("Limit this quill to certain apps")
        .accessibilityLabel("Apps")
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

    private var usageText: String {
        switch snippet.useCount {
        case 0: "Not used yet"
        case 1: "Used once · \(snippet.keysSaved.formatted()) keys saved"
        default: "Used \(snippet.useCount.formatted()) times · \(snippet.keysSaved.formatted()) keys saved"
        }
    }

    private var lastUsedText: String {
        guard let lastUsed = snippet.lastUsed else { return "Never used" }
        return "Last used " + lastUsed.formatted(.relative(presentation: .named))
    }
}

/// Green when the quill expands, red when it's off.
private struct StatusDot: View {
    let isOn: Bool
    let help: String

    var body: some View {
        Circle()
            .fill(isOn ? Color.green : Color.red)
            .frame(width: 10, height: 10)
            .help(help)
            .accessibilityElement()
            .accessibilityLabel(isOn ? "On" : "Off")
            .accessibilityIdentifier("quill-status")
    }
}

/// A tinted capsule: coloured symbol and text on a faint wash of the same colour.
struct PillLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

extension View {
    /// A small label above an option pill, saying what the pill sets.
    fileprivate func pillCaption(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .accessibilityHidden(true)
            self
        }
    }
}

/// A coloured pill that opens a menu of choices.
private struct OptionPill<Content: View>: View {
    let title: String
    let symbol: String
    let color: Color
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
                .pickerStyle(.inline)
        } label: {
            PillLabel(title: title, symbol: symbol, color: color)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(title)
    }
}

/// App names from bundle identifiers.
enum AppInfo {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
