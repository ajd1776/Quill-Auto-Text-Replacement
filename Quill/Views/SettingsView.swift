import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, suggestions, effects, shortcuts, backup, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// The tabs along the top of Settings: five at most, so About lives inside General.
    static let tabs: [SettingsPane] = [.general, .suggestions, .effects, .shortcuts, .backup]
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

/// Quill Settings: one page in the main window, with an row of tabs
/// along the bottom, just above the main tab bar. Five tabs at most; About sits at the bottom of General.
struct SettingsView: View {
    @AppStorage("settingsPane") private var stored: SettingsPane = .general

    private var pane: SettingsPane { stored == .about ? .general : stored }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: 0) {
                switch pane {
                case .general, .about:
                    GeneralSettingsPane()
                    AboutSettingsPane()
                case .suggestions: SuggestionSettingsPane()
                case .effects: EffectsSettingsPane()
                case .shortcuts: ShortcutSettingsPane()
                case .backup: BackupSettingsPane()
                }
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        SettingsTabBar(selection: $stored, current: pane)
            .padding(.top, 10)
        }
        .navigationTitle("Settings")
    }
}

/// The Settings panes as a compact row of text tabs at the bottom of the page, just
/// above the main tab bar, the current one in a tinted capsule.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsPane
    let current: SettingsPane

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsPane.tabs) { tab in
                let isSelected = tab == current
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(isSelected ? Color.accentColor.opacity(0.16) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
            }
        }
        .padding(4)
        .background(Surface.bar, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings tabs")
    }
}

/// Settings panes share one look: grouped, not scrolling, sized to their content.
private extension View {
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
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
                Toggle("Remove the space after a quill", isOn: Binding(
                    get: { !state.addsSpaceAfterSnippet },
                    set: { state.addsSpaceAfterSnippet = !$0 }
                ))
            } header: {
                Text("Expansion")
            } footer: {
                FooterText(state.addsSpaceAfterSnippet
                    ? "The space you type to expand a shortcut stays after the text."
                    : "The space you type to expand a shortcut is removed, so the text ends right after the quill. Return, Tab and punctuation still go through.")
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
        panel.message = "Choose apps where Quill shouldn't expand quills."
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
                        StyleTile(style: style, isSelected: state.defaultAnimations.contains(style),
                                  isDimmed: reduceMotion && !style.survivesReduceMotion) {
                            withAnimation(.snappy(duration: 0.15)) { state.toggleDefaultAnimation(style) }
                        }
                    }
                }
                .padding(.vertical, 4)

                if state.defaultAnimations.count > 1 {
                    Label("\(state.defaultAnimations.count) effects are on: \(state.defaultAnimationsTitle). They play together, which can look busy.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("multiple-effects-warning")
                }

                let heldBack = state.defaultAnimations.filter { reduceMotion && !$0.survivesReduceMotion }
                if !heldBack.isEmpty {
                    Label("Reduce Motion is on, so \(heldBack.map(\.title).joined(separator: " and ")) won't play. Turn on Play animations anyway below to include \(heldBack.count == 1 ? "it" : "them").",
                          systemImage: "figure.walk.motion")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                AnimationPreview(
                    styles: state.defaultAnimations,
                    speed: state.typewriterSpeed,
                    trigger: sample.trigger,
                    expansion: sample.expansion,
                    reduceMotion: reduceMotion
                )

                if state.defaultAnimations.contains(.typewriter) {
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
                Text("Default Animations")
            } footer: {
                FooterText((state.defaultAnimations.count > 1
                            ? "Click an effect to add or remove it; the ones chosen play together."
                            : state.defaultAnimation.explanation + " Click more effects to combine them.")
                           + " Any quill can use a different effect from its editor.")
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
                FooterText("Plays each time a quill expands.")
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
                LabeledContent("Search quills") {
                    HotkeyRecorder(hotkey: $state.searchHotkey, label: "Search quills")
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
                LabeledContent("New quill / group") { Text("⌘N / ⇧⌘N").foregroundStyle(.secondary) }
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
                FooterText("Quill saves a copy of your quills once a day and keeps the last seven.")
            }

            Section {
                LabeledContent("Export") {
                    Button("Export Quills…") { state.exportLibrary() }
                }
                LabeledContent("Import") {
                    Button("Import Quills…", action: importFile)
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
                FooterText("Exports include every quill, group and usage count. Importing skips shortcuts Quill already has.")
            }

            Section {
                LabeledContent("Library file") {
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
                LabeledContent("Quills", value: state.store.snippets.count.formatted())
                LabeledContent("Groups", value: state.store.groups.count.formatted())
                LabeledContent("Keys saved", value: state.store.totalKeysSaved.formatted())
                LabeledContent("Library file") {
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
                Text("MIT licence. Your quills and history stay on this Mac; the only network request is the daily update check against GitHub Releases.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
