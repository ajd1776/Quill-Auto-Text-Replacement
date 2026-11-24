import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, suggestions, effects, shortcuts, backup, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .suggestions: "text.bubble.fill"
        case .effects: "sparkles"
        case .shortcuts: "command"
        case .backup: "externaldrive.fill"
        case .about: "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: .gray
        case .suggestions: .blue
        case .effects: .purple
        case .shortcuts: .indigo
        case .backup: .teal
        case .about: .blue
        }
    }
}

/// Quill Settings: a toolbar of panes, reopening on the last one used.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("settingsPane") private var pane: SettingsPane = .general

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPane.general)
            SuggestionSettingsPane()
                .tabItem { Label("Suggestions", systemImage: "text.bubble") }
                .tag(SettingsPane.suggestions)
            EffectsSettingsPane()
                .tabItem { Label("Effects", systemImage: "sparkles") }
                .tag(SettingsPane.effects)
            ShortcutSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(SettingsPane.shortcuts)
            BackupSettingsPane()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
                .tag(SettingsPane.backup)
            AboutSettingsPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsPane.about)
        }
        .frame(width: 580)
        .onAppear { state.windowAppeared("settings") }
        .onDisappear { state.windowDisappeared("settings") }
    }
}

/// Settings panes share one look: grouped, not scrolling, sized to their content.
private extension View {
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Section footer text, left-aligned like System Settings.
private struct FooterText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var state
    @AppStorage(AppState.showMenuBarExtraKey) private var showsMenuBarExtra = true
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                Picker("Menu bar icon", selection: Binding(
                    get: { state.menuBarIcon },
                    set: { state.menuBarIcon = $0 }
                )) {
                    ForEach(MenuBarIcon.allCases) { icon in
                        Label {
                            Text(icon.title)
                        } icon: {
                            Image(nsImage: icon.image(isOn: true))
                        }
                        .tag(icon)
                    }
                }
                .disabled(!showsMenuBarExtra)
                Toggle("Show in menu bar", isOn: $showsMenuBarExtra)
                    .onChange(of: showsMenuBarExtra) { state.updateActivationPolicy() }
            } footer: {
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if !showsMenuBarExtra {
                    FooterText("Quill keeps a Dock icon while the menu bar icon is hidden.")
                }
            }

            Section {
                Toggle("Add a space after a snippet", isOn: Binding(
                    get: { state.addsSpaceAfterSnippet },
                    set: { state.addsSpaceAfterSnippet = $0 }
                ))
            } header: {
                Text("Expansion")
            } footer: {
                FooterText(state.addsSpaceAfterSnippet
                    ? "The space you type to expand a shortcut stays after the text."
                    : "The space you type to expand a shortcut is removed, so the text ends right after the snippet. Return, Tab and punctuation still go through.")
            }

            Section {
                if state.excludedBundleIDs.isEmpty {
                    Text("Quill works in every app.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.excludedBundleIDs.sorted(), id: \.self) { bundleID in
                        PausedAppRow(bundleID: bundleID) { state.setExcluded(bundleID, false) }
                    }
                }
            } header: {
                HStack {
                    Text("Paused Apps")
                    Spacer()
                    Button("Add App…", action: chooseApp).controlSize(.small)
                }
            } footer: {
                FooterText("Quill never expands or suggests in these apps. You can also pause the app you're using from the menu bar.")
            }

            UpdateSettingsSection()

            Section {
                LabeledContent("Accessibility") {
                    if state.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Privacy Settings…") {
                            state.requestAccess()
                            state.openAccessibilitySettings()
                        }
                    }
                }
                Toggle("Keep expansion history", isOn: Binding(
                    get: { state.keepsHistory },
                    set: { state.keepsHistory = $0 }
                ))
            } header: {
                Text("Privacy")
            } footer: {
                FooterText("Quill needs Accessibility access to notice shortcuts and type the replacement. What you type never leaves this Mac, and macOS never shows password fields to Quill.")
            }
        }
        .settingsPaneStyle()
        .onAppear { launchesAtLogin = LoginItem.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
            launchesAtLogin = LoginItem.isEnabled
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Pause Quill"
        panel.message = "Choose apps where Quill shouldn't expand snippets."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { state.setExcluded(bundleID, true) }
        }
    }
}

private struct PausedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 10) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                .lineLimit(1)
            Spacer()
            Button("Remove", systemImage: "minus.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop Pausing in This App")
        }
    }
}

// MARK: - Suggestions

struct SuggestionSettingsPane: View {
    @Environment(AppState.self) private var state
    @State private var sample = SuggestionModel()

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                Toggle("Show suggestions as you type", isOn: $state.showsSuggestions)
                Toggle("Include partial matches", isOn: $state.showsPartialSuggestions)
                    .disabled(!state.showsSuggestions)
            } footer: {
                FooterText("Like the macOS text replacement bubble: Space or punctuation accepts an exact match, Tab accepts the highlighted suggestion, ↑↓ choose and Esc dismisses. Partial matches appear after 2 characters of a shortcut. The bubble sits above the text, and stays hidden in apps that don't report the cursor position.")
            }

            Section("Preview") {
                HStack {
                    Spacer()
                    SuggestionBubbleView(model: sample)
                        .padding(.vertical, 10)
                    Spacer()
                }
                .opacity(state.showsSuggestions ? 1 : 0.4)
            }
        }
        .settingsPaneStyle()
        .onAppear(perform: makeSample)
        .onChange(of: state.showsPartialSuggestions) { makeSample() }
    }

    /// Shows the shortcut prefix most of your snippets share, so partial matches are visible.
    private func makeSample() {
        let snippets = state.store.activeSnippets.filter { $0.mode == .afterDelimiter && $0.trigger.count >= 3 }
        let families = Dictionary(grouping: snippets) { String($0.trigger.prefix(2)) }
        let family = (families.max { $0.value.count < $1.value.count }?.value ?? [])
            .sorted { $0.trigger.count < $1.trigger.count }
        guard let first = family.first else {
            sample.items = [ExpansionEngine.Suggestion(snippet: Snippet(trigger: "eAD", expansion: "name@example.com"), typedCount: 3)]
            return
        }
        var items = [ExpansionEngine.Suggestion(snippet: first, typedCount: first.trigger.count)]
        if state.showsPartialSuggestions {
            items += family.dropFirst().prefix(2).compactMap { snippet in
                snippet.trigger.hasPrefix(first.trigger)
                    ? ExpansionEngine.Suggestion(snippet: snippet, typedCount: first.trigger.count)
                    : nil
            }
        }
        sample.items = items
        sample.highlighted = 0
    }
}

// MARK: - Effects

struct EffectsSettingsPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        @Bindable var state = state
        let sample = state.previewSnippet
        let reduceMotion = systemReduceMotion && !state.animatesWithReduceMotion

        Form {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(ReplacementAnimation.allCases) { style in
                        StyleTile(style: style, isSelected: state.defaultAnimation == style,
                                  isDimmed: reduceMotion && !style.survivesReduceMotion) {
                            state.defaultAnimation = style
                        }
                    }
                }
                .padding(.vertical, 4)

                AnimationPreview(
                    style: state.defaultAnimation,
                    speed: state.typewriterSpeed,
                    trigger: sample.trigger,
                    expansion: sample.expansion,
                    reduceMotion: reduceMotion
                )

                if state.defaultAnimation == .typewriter {
                    LabeledContent("Typing speed") {
                        Slider(value: $state.typewriterSpeed, in: 15...120) {
                            Text("Typing speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise").accessibilityLabel("Slower")
                        } maximumValueLabel: {
                            Image(systemName: "hare").accessibilityLabel("Faster")
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)
                    }
                }
            } header: {
                Text("Default Animation")
            } footer: {
                FooterText(state.defaultAnimation.explanation + " Any snippet can use a different style, from its editor or right-click menu.")
            }

            if systemReduceMotion {
                Section {
                    Toggle("Play animations anyway", isOn: $state.animatesWithReduceMotion)
                } header: {
                    Text("Reduce Motion Is On")
                } footer: {
                    FooterText(state.animatesWithReduceMotion
                        ? "Quill plays every animation even though Reduce Motion is on in System Settings."
                        : "Following your Reduce Motion setting: only None, Pop Badge, Glow and Fade In play, and they fade without moving.")
                }
            }

            Section {
                Picker("Sound", selection: Binding(
                    get: { state.soundName },
                    set: { name in
                        state.soundName = name
                        state.playSound()
                    }
                )) {
                    Text("None").tag(String?.none)
                    Divider()
                    ForEach(AppState.systemSounds, id: \.self) { Text($0).tag(Optional($0)) }
                }
                LabeledContent("Volume") {
                    HStack {
                        Slider(value: $state.soundVolume, in: 0.05...1) { Text("Volume") }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                        Button("Play", systemImage: "play.fill") { state.playSound() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Play Sound")
                    }
                }
                .disabled(state.soundName == nil)
            } header: {
                Text("Sound")
            } footer: {
                FooterText("Plays each time a snippet expands.")
            }
        }
        .settingsPaneStyle()
    }
}

private struct StyleTile: View {
    let style: ReplacementAnimation
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: style.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(style.title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.6)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .help(style.explanation)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                LabeledContent("Turn Quill on or off") {
                    HotkeyRecorder(hotkey: $state.toggleHotkey, label: "Turn Quill on or off")
                }
                LabeledContent("Search snippets") {
                    HotkeyRecorder(hotkey: $state.searchHotkey, label: "Search snippets")
                }
            } footer: {
                if state.hotkeyConflicts.isEmpty {
                    FooterText("These work in any app. Include ⌘, ⌃ or ⌥, and press Esc to cancel.")
                } else {
                    Label("A shortcut is already used by another app or by the other Quill shortcut. Choose a different one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("While Typing") {
                LabeledContent("Accept a suggestion") { Text("Space, punctuation or ⇥").foregroundStyle(.secondary) }
                LabeledContent("Dismiss a suggestion") { Text("esc").foregroundStyle(.secondary) }
                LabeledContent("Undo an expansion") { Text("⌫ straight after it").foregroundStyle(.secondary) }
            }

            Section("In the Library") {
                LabeledContent("New snippet / group") { Text("⌘N / ⇧⌘N").foregroundStyle(.secondary) }
                LabeledContent("Duplicate") { Text("⌘D").foregroundStyle(.secondary) }
                LabeledContent("Overview") { Text("⌘0").foregroundStyle(.secondary) }
                LabeledContent("Turn Quill on or off") { Text("⇧⌘P").foregroundStyle(.secondary) }
            }
        }
        .settingsPaneStyle()
    }
}

// MARK: - Backup

struct BackupSettingsPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                Toggle("Keep daily backups", isOn: $state.keepsDailyBackups)
                LabeledContent("Backups folder") {
                    Button("Show in Finder") { state.showBackups() }
                }
            } footer: {
                FooterText("Quill saves a copy of your snippets once a day and keeps the last seven.")
            }

            Section {
                LabeledContent("Export") {
                    Button("Export Snippets…") { state.exportLibrary() }
                }
                LabeledContent("Import") {
                    Button("Import Snippets…", action: importFile)
                }
                LabeledContent("macOS Text Replacements") {
                    Button("Import…") {
                        openLibrary()
                        state.beginSystemImport()
                    }
                }
            } header: {
                Text("Move Between Macs")
            } footer: {
                FooterText("Exports include every snippet, group and usage count. Importing skips shortcuts Quill already has.")
            }

            Section {
                LabeledContent("Snippets file") {
                    Button("Show in Finder") {
                        state.store.save()
                        NSWorkspace.shared.activateFileViewerSelecting([SnippetStore.fileURL])
                    }
                }
            }
        }
        .settingsPaneStyle()
    }

    private func openLibrary() {
        NSApp.activate()
        openWindow(id: WindowID.library)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .propertyList, .xml]
        panel.message = "Choose a Quill export, a daily backup, or a Text Substitutions file."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLibrary()
        state.importFile(url)
    }
}

/// Version, where Quill comes from, and where its files live.
struct AboutSettingsPane: View {
    @Environment(AppState.self) private var state

    private var repositoryURL: URL? {
        UpdateChecker.repository.flatMap { URL(string: "https://github.com/\($0)") }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quill").font(.title.weight(.bold))
                        Text("Version \(UpdateChecker.currentVersion)")
                            .foregroundStyle(.secondary)
                        Text("System-wide text expander for macOS.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Library") {
                LabeledContent("Snippets", value: state.store.snippets.count.formatted())
                LabeledContent("Groups", value: state.store.groups.count.formatted())
                LabeledContent("Keys saved", value: state.store.totalKeysSaved.formatted())
                LabeledContent("Snippets file") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([SnippetStore.fileURL])
                    }
                }
            }

            Section("Links") {
                if let repositoryURL {
                    Link(destination: repositoryURL) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: repositoryURL.appending(path: "issues")) {
                        Label("Report a Problem", systemImage: "exclamationmark.bubble")
                    }
                    Link(destination: repositoryURL.appending(path: "releases")) {
                        Label("Release Notes", systemImage: "doc.text")
                    }
                }
            }

            Section {
                Text("MIT licence. Your snippets and history stay on this Mac; the only network request is the daily update check against GitHub Releases.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
