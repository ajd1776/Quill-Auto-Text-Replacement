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
    @State private var isPickingIcon = false

    private let inset: CGFloat = 28
    private let editorFontSize: CGFloat = 15

    private var group: SnippetGroup? { state.store.group(for: snippet) }
    private var tint: Color { group?.color.color ?? .accentColor }

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
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(snippet.trigger.isEmpty ? "New Snippet" : snippet.trigger)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Text", systemImage: "doc.on.doc") {
                    state.copyExpansion(snippet.id)
                }
                .help("Copy Text")
                .disabled(snippet.expansion.isEmpty)

                Button("Delete Snippet", systemImage: "trash", action: onDelete)
                    .help("Delete Snippet")
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
                isPickingIcon = true
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
            .help("Change Icon")
            .accessibilityLabel("Change icon")
            .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
                IconPicker(current: snippet.symbol, tint: tint, defaultTitle: "Use Group Icon") { snippet.symbol = $0 }
            }

            VStack(alignment: .leading, spacing: 5) {
                TextField("Shortcut", text: $snippet.trigger, prompt: Text("Shortcut"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .focused($isTriggerFocused)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Shortcut")

                HStack(spacing: 8) {
                    if let problem {
                        StatusPill(text: problem, symbol: "exclamationmark.triangle.fill", color: .orange)
                    } else if !state.store.isActive(snippet) {
                        StatusPill(text: snippet.isEnabled ? "Group \u{201C}\(group?.name ?? "")\u{201D} is off" : "Off",
                                   symbol: "pause.circle.fill", color: .secondary)
                    } else {
                        StatusPill(text: "Ready", symbol: "checkmark.circle.fill", color: .green)
                        Text(statusDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Toggle("Snippet on", isOn: $snippet.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(snippet.isEnabled ? "Turn Off" : "Turn On")
                .accessibilityLabel("Snippet on")
        }
        .padding(.horizontal, inset)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background {
            // A soft wash of the group colour behind the header.
            LinearGradient(colors: [tint.opacity(0.14), tint.opacity(0)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var statusDetail: String {
        var parts = [snippet.mode == .immediate ? "Expands as soon as it's typed" : "Expands after a space or punctuation"]
        if snippet.matchesAnyCase { parts.append("any capitals") }
        if !snippet.appBundleIDs.isEmpty { parts.append("only in \(appsTitle)") }
        return parts.joined(separator: " · ")
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

                Text(countText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Picker(selection: $snippet.groupID) {
                    Text("No Group").tag(SnippetGroup.ID?.none)
                    if !state.store.groups.isEmpty { Divider() }
                    ForEach(state.store.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                } label: {
                    FooterIcon(symbol: "folder", label: "Group")
                }
                .fixedSize()

                Picker(selection: $snippet.mode) {
                    ForEach(ExpansionMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    FooterIcon(symbol: "keyboard", label: "Expands")
                }
                .fixedSize()

                // Spelled out because Binding has its own animation(_:) method.
                Picker(selection: Binding(get: { snippet.animation }, set: { snippet.animation = $0 })) {
                    Text("Default (\(state.defaultAnimation.title))").tag(ReplacementAnimation?.none)
                    Divider()
                    ForEach(ReplacementAnimation.allCases) { style in
                        Label(style.title, systemImage: style.symbol).tag(Optional(style))
                    }
                } label: {
                    FooterIcon(symbol: "sparkles", label: "Animation")
                }
                .fixedSize()
            }

            HStack(spacing: 16) {
                appsMenu

                Toggle("Match any capitals", isOn: $snippet.matchesAnyCase)
                    .toggleStyle(.checkbox)
                    .help("Also expand when typed in other capitals, matching the text's capitals to how you typed it")

                Spacer(minLength: 10)

                Text(usageText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(lastUsedText)
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
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
            Label(appsTitle, systemImage: snippet.appBundleIDs.isEmpty ? "macwindow.on.rectangle" : "app.badge.checkmark")
        }
        .fixedSize()
        .help("Limit this snippet to certain apps")
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

/// Small coloured capsule for the snippet's status.
private struct StatusPill: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

private struct FooterIcon: View {
    let symbol: String
    let label: String

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
            .help(label)
    }
}

/// App names from bundle identifiers.
enum AppInfo {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
