import AppKit
import ApplicationServices
import Observation
import ServiceManagement
import UniformTypeIdentifiers

/// What's selected in the library sidebar.
enum SidebarItem: Hashable {
    case overview
    case history
    case settings
    case snippet(Snippet.ID)

    var snippetID: Snippet.ID? {
        if case .snippet(let id) = self { return id }
        return nil
    }
}

/// The pages in the library window's toolbar.
enum AppPage: String, CaseIterable, Identifiable {
    case snippets, stats, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .snippets: "Quills"
        case .stats: "Stats"
        case .history: "History"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .snippets: "text.quote"
        case .stats: "chart.bar.xaxis"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// What the Snippets page shows, chosen in its sidebar.
enum SnippetScope: Hashable {
    case all, recent, enabled, disabled, tokens, ungrouped
    case group(SnippetGroup.ID)
}

/// How the Snippets page lays snippets out.
enum SnippetLayout: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
}

/// App-wide state shared by the menu bar menu, library window, search panel and settings.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let store = SnippetStore()
    let history = ExpansionHistory()
    let updates = UpdateChecker()
    private let engine = ExpansionEngine.shared
    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: Status

    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var isEngineRunning = false
    private(set) var isPaused = false
    private(set) var pausedUntil: Date?
    private(set) var excludedBundleIDs = Set<String>()
    /// The app you were last typing in, for "Pause in <app>".
    private(set) var lastExternalApp: NSRunningApplication?

    enum Status: Equatable {
        case on
        case off
        case pausedUntil(Date)
        case pausedInApp(String)
        case needsAccess
    }

    var status: Status {
        #if DEBUG
        if CommandLine.arguments.contains("-QuillDemoNeedsAccess") { return .needsAccess }
        if DemoLibrary.isActive { return .on }
        #endif
        if !isTrusted || !isEngineRunning { return .needsAccess }
        if isPaused { return pausedUntil.map(Status.pausedUntil) ?? .off }
        if let app = lastExternalApp, let id = app.bundleIdentifier, excludedBundleIDs.contains(id) {
            return .pausedInApp(app.localizedName ?? "This App")
        }
        return .on
    }

    // MARK: Preferences

    var defaultAnimation: ReplacementAnimation = .popBadge {
        didSet { defaults.set(defaultAnimation.rawValue, forKey: Keys.defaultAnimation) }
    }

    var typewriterSpeed: Double = 45 {
        didSet {
            defaults.set(typewriterSpeed, forKey: Keys.typewriterSpeed)
            engine.typewriterSpeed = typewriterSpeed
        }
    }

    var animatesWithReduceMotion = false {
        didSet {
            defaults.set(animatesWithReduceMotion, forKey: Keys.animatesWithReduceMotion)
            engine.honoursReduceMotion = !animatesWithReduceMotion
        }
    }

    var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !animatesWithReduceMotion
    }

    var showsSuggestions = true {
        didSet {
            defaults.set(showsSuggestions, forKey: Keys.showsSuggestions)
            engine.suggestionsEnabled = showsSuggestions
        }
    }

    /// Whether the space typed to trigger a snippet stays after the text.
    var addsSpaceAfterSnippet = true {
        didSet {
            defaults.set(addsSpaceAfterSnippet, forKey: Keys.addsSpaceAfterSnippet)
            engine.keepsTriggerSpace = addsSpaceAfterSnippet
        }
    }

    var showsPartialSuggestions = true {
        didSet {
            defaults.set(showsPartialSuggestions, forKey: Keys.showsPartialSuggestions)
            engine.partialSuggestionsEnabled = showsPartialSuggestions
        engine.keepsTriggerSpace = addsSpaceAfterSnippet
        }
    }

    var bubblePosition: BubblePosition = .below {
        didSet { defaults.set(bubblePosition.rawValue, forKey: Keys.bubblePosition) }
    }

    /// A macOS system sound name, or nil for silence.
    var soundName: String? {
        didSet { defaults.set(soundName, forKey: Keys.soundName) }
    }

    var soundVolume: Double = 0.5 {
        didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) }
    }

    var menuBarIcon: MenuBarIcon = .solidNib {
        didSet { defaults.set(menuBarIcon.rawValue, forKey: Keys.menuBarIcon) }
    }

    var keepsHistory = true {
        didSet {
            defaults.set(keepsHistory, forKey: Keys.keepsHistory)
            if !keepsHistory { history.clear() }
        }
    }

    var keepsDailyBackups = true {
        didSet { defaults.set(keepsDailyBackups, forKey: Keys.keepsDailyBackups) }
    }

    var sortOrder: SnippetSortOrder = .shortcut {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    var toggleHotkey: Hotkey? {
        didSet {
            save(toggleHotkey, forKey: Keys.toggleHotkey)
            registerHotkeys()
        }
    }

    var searchHotkey: Hotkey? {
        didSet {
            save(searchHotkey, forKey: Keys.searchHotkey)
            registerHotkeys()
        }
    }

    private(set) var hotkeyConflicts = Set<HotkeyAction>()

    // MARK: Library window

    var scope: SnippetScope = .all

    /// What's selected in the sidebar: Stats, History, or one or more snippets.
    var selection: Set<SidebarItem> = [.overview]

    /// Which area the window shows, worked out from the sidebar selection. Setting it selects that area,
    /// so menus, ⌘K and the menu bar panel can switch areas; Settings opens its own window.
    var page: AppPage {
        get {
            if selection.contains(.history) { return .history }
            if selection.contains(.overview) { return .stats }
            if selection.contains(.settings) { return .settings }
            return .snippets
        }
        set {
            switch newValue {
            case .stats: selection = [.overview]
            case .history: selection = [.history]
            case .snippets: if selection.contains(where: { $0.snippetID == nil }) { selection = [] }
            case .settings: showSettings()
            }
        }
    }

    /// The snippets a scope covers, before search and sorting.
    func snippets(in scope: SnippetScope) -> [Snippet] {
        switch scope {
        case .all: store.snippets
        case .recent: store.snippets.filter { $0.lastUsed != nil }
        case .enabled: store.snippets.filter(store.isActive)
        case .disabled: store.snippets.filter { !store.isActive($0) }
        case .tokens: store.snippets.filter { TokenRenderer.containsTokens($0.expansion) }
        case .ungrouped: store.snippets(in: nil)
        case .group(let id): store.snippets(in: id)
        }
    }

    func title(for scope: SnippetScope) -> String {
        switch scope {
        case .all: "All Quills"
        case .recent: "Recently Used"
        case .enabled: "On"
        case .disabled: "Off"
        case .tokens: "With Tokens"
        case .ungrouped: "Ungrouped"
        case .group(let id): store.group(id)?.name ?? "Group"
        }
    }
    var importSession: ImportSession?
    var alertMessage: (title: String, message: String)?
    var isShowingFileImporter = false
    var renamingGroupID: SnippetGroup.ID?
    var isShowingPalette = false
    var isShowingPacks = false
    var colorPickerGroupID: SnippetGroup.ID?
    /// What the icon picker sheet is choosing an icon for, when opened from a menu.
    var iconPickerTarget: IconTarget?

    enum IconTarget: Identifiable, Hashable {
        case group(SnippetGroup.ID)
        case snippet(Snippet.ID)
        var id: Self { self }
    }
    var deletingGroupID: SnippetGroup.ID?

    var selectedSnippetIDs: Set<Snippet.ID> {
        Set(selection.compactMap(\.snippetID))
    }

    @ObservationIgnored var openLibraryAction: (() -> Void)?
    // MARK: Firing Range

    /// One expansion fired in the Firing Range.
    struct RangeHit: Identifiable {
        let id = UUID()
        let snippetID: Snippet.ID
        let trigger: String
        let text: String
        let style: ReplacementAnimation
        let date = Date()
        var keysSaved: Int { max(0, text.count - trigger.count) }

        init(_ expansion: ExpansionEngine.Expansion) {
            snippetID = expansion.snippet.id
            trigger = expansion.snippet.trigger
            text = expansion.renderedText
            style = expansion.style
        }
    }

    /// Expansions fired in the Firing Range since Quill opened, newest first.
    var rangeHits: [RangeHit] = []
    /// The effect every quill uses in the Firing Range, or nil for each quill's own.
    var rangeEffect: ReplacementAnimation?

    /// True while you're typing in the Firing Range window.
    var isFiringRangeKey: Bool {
        guard NSApp.isActive, let window = NSApp.keyWindow else { return false }
        return window.identifier?.rawValue.hasPrefix(WindowID.firingRange) == true || window.title == "Firing Range"
    }

    /// Opens the Firing Range window (set by the menu bar label, which has the SwiftUI environment).
    @ObservationIgnored var openFiringRangeAction: (() -> Void)?

    /// Settings live in the main window, as a page in the sidebar.
    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane") }
        NSApp.activate()
        openLibraryAction?()
        selection = [.settings]
    }

    func showFiringRange() {
        NSApp.activate()
        openFiringRangeAction?()
    }
    @ObservationIgnored private var visibleWindows = Set<String>()
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    private enum Keys {
        static let defaultAnimation = "defaultAnimation"
        static let typewriterSpeed = "typewriterSpeed"
        static let animatesWithReduceMotion = "animatesWithReduceMotion"
        static let showsSuggestions = "showsSuggestions"
        static let showsPartialSuggestions = "showsPartialSuggestions"
        static let addsSpaceAfterSnippet = "addsSpaceAfterSnippet"
        static let bubblePosition = "bubblePosition"
        static let soundName = "soundName"
        static let soundVolume = "soundVolume"
        static let keepsDailyBackups = "keepsDailyBackups"
        static let keepsHistory = "keepsHistory"
        static let menuBarIcon = "menuBarIcon"
        static let sortOrder = "sortOrder"
        static let isPaused = "isPaused"
        static let pausedUntil = "pausedUntil"
        static let excludedApps = "excludedApps"
        static let toggleHotkey = "toggleHotkey"
        static let searchHotkey = "searchHotkey"
    }

    static let showMenuBarExtraKey = "showMenuBarExtra"

    static let systemSounds: [String] = {
        let folder = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }()

    // MARK: Setup

    private init() {
        loadPreferences()
        configureEngine()
        startEngineIfPossible()
        watchFrontmostApp()
        HotKeyCenter.shared.handler = { [weak self] action in self?.perform(action) }
        registerHotkeys()
        if keepsDailyBackups { store.makeDailyBackup() }
        if let failure = store.loadFailure {
            alertMessage = ("Quills File Couldn't Be Read", failure)
        }
        monitor()
    }

    private func loadPreferences() {
        defaultAnimation = defaults.string(forKey: Keys.defaultAnimation).flatMap(ReplacementAnimation.init) ?? .popBadge
        if defaults.object(forKey: Keys.typewriterSpeed) != nil {
            typewriterSpeed = defaults.double(forKey: Keys.typewriterSpeed)
        }
        animatesWithReduceMotion = defaults.bool(forKey: Keys.animatesWithReduceMotion)
        showsSuggestions = defaults.object(forKey: Keys.showsSuggestions) as? Bool ?? true
        showsPartialSuggestions = defaults.object(forKey: Keys.showsPartialSuggestions) as? Bool ?? true
        addsSpaceAfterSnippet = defaults.object(forKey: Keys.addsSpaceAfterSnippet) as? Bool ?? true
        bubblePosition = defaults.string(forKey: Keys.bubblePosition).flatMap(BubblePosition.init) ?? .below
        soundName = defaults.string(forKey: Keys.soundName)
        if defaults.object(forKey: Keys.soundVolume) != nil {
            soundVolume = defaults.double(forKey: Keys.soundVolume)
        }
        keepsDailyBackups = defaults.object(forKey: Keys.keepsDailyBackups) as? Bool ?? true
        keepsHistory = defaults.object(forKey: Keys.keepsHistory) as? Bool ?? true
        menuBarIcon = defaults.string(forKey: Keys.menuBarIcon).flatMap(MenuBarIcon.init) ?? .solidNib
        sortOrder = defaults.string(forKey: Keys.sortOrder).flatMap(SnippetSortOrder.init) ?? .shortcut
        isPaused = defaults.bool(forKey: Keys.isPaused)
        pausedUntil = defaults.object(forKey: Keys.pausedUntil) as? Date
        excludedBundleIDs = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
        toggleHotkey = loadHotkey(forKey: Keys.toggleHotkey)
        searchHotkey = loadHotkey(forKey: Keys.searchHotkey)
    }

    private func configureEngine() {
        engine.update(snippets: store.activeSnippets)
        store.onChange = { [unowned self] in self.engine.update(snippets: self.store.activeSnippets) }
        engine.isPaused = isPaused
        engine.excludedBundleIDs = excludedBundleIDs
        engine.typewriterSpeed = typewriterSpeed
        engine.honoursReduceMotion = !animatesWithReduceMotion
        engine.suggestionsEnabled = showsSuggestions
        engine.partialSuggestionsEnabled = showsPartialSuggestions
        engine.keepsTriggerSpace = addsSpaceAfterSnippet
        engine.styleResolver = { [unowned self] snippet in
            if self.isFiringRangeKey, let effect = self.rangeEffect { return effect }
            return snippet.animation ?? self.defaultAnimation
        }
        engine.onExpanded = { [unowned self] expansion in self.didExpand(expansion) }
        engine.onUndone = { [unowned self] id in
            if self.isFiringRangeKey {
                if let index = self.rangeHits.firstIndex(where: { $0.snippetID == id }) { self.rangeHits.remove(at: index) }
                return
            }
            self.store.undoUse(id)
            self.history.removeLatest(for: id)
        }
        engine.onNeedsInput = { snippet, fields, completion in
            FillInController.shared.present(snippet: snippet, fields: fields, completion: completion)
        }
        engine.onSuggestionsChanged = { items, highlighted in
            SuggestionBubbleController.shared.update(items, highlighted: highlighted)
        }
    }

    private func watchFrontmostApp() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            lastExternalApp = front
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
    }

    /// Accessibility access can change at any time in System Settings, and timed pauses run out.
    private func monitor() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }

                if let until = self.pausedUntil, Date() >= until {
                    self.setOn(true)
                }

                let trusted = AXIsProcessTrusted()
                guard trusted != self.isTrusted || (trusted && !self.isEngineRunning) else { continue }
                self.isTrusted = trusted
                if trusted {
                    self.startEngineIfPossible()
                } else {
                    self.engine.stop()
                    self.isEngineRunning = false
                }
            }
        }
    }

    // MARK: Accessibility access

    private func startEngineIfPossible() {
        guard isTrusted else { return }
        isEngineRunning = engine.start()
    }

    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isTrusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        startEngineIfPossible()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: On, off and pausing

    var isOn: Bool { !isPaused }

    func setOn(_ on: Bool, announce: Bool = false) {
        isPaused = !on
        pausedUntil = nil
        persistPause()
        if announce { OverlayPresenter.shared.showToggleHUD(isOn: on) }
    }

    func pause(minutes: Int) {
        pause(until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func pauseUntilTomorrowMorning() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        pause(until: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
    }

    private func pause(until date: Date) {
        isPaused = true
        pausedUntil = date
        persistPause()
    }

    private func persistPause() {
        engine.isPaused = isPaused
        defaults.set(isPaused, forKey: Keys.isPaused)
        defaults.set(pausedUntil, forKey: Keys.pausedUntil)
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded {
            excludedBundleIDs.insert(bundleID)
        } else {
            excludedBundleIDs.remove(bundleID)
        }
        defaults.set(excludedBundleIDs.sorted(), forKey: Keys.excludedApps)
        engine.excludedBundleIDs = excludedBundleIDs
    }

    // MARK: Hotkeys

    func registerHotkeys() {
        var hotkeys: [HotkeyAction: Hotkey] = [:]
        if let toggleHotkey { hotkeys[.toggleQuill] = toggleHotkey }
        if let searchHotkey, searchHotkey != toggleHotkey { hotkeys[.searchSnippets] = searchHotkey }
        var conflicts = HotKeyCenter.shared.register(hotkeys)
        if let searchHotkey, searchHotkey == toggleHotkey { conflicts.insert(.searchSnippets) }
        hotkeyConflicts = conflicts
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleQuill: setOn(isPaused, announce: true)
        case .searchSnippets: SearchPanelController.shared.toggle()
        }
    }

    private func loadHotkey(forKey key: String) -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private func save(_ hotkey: Hotkey?, forKey key: String) {
        if let hotkey, let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Expansion

    private func didExpand(_ expansion: ExpansionEngine.Expansion) {
        if isFiringRangeKey {
            // Practice doesn't count towards Stats or History.
            rangeHits.insert(RangeHit(expansion), at: 0)
            playSound()
            OverlayPresenter.shared.play(expansion.style, trigger: expansion.snippet.trigger, text: expansion.renderedText)
            return
        }
        store.recordUse(expansion.snippet.id)
        if keepsHistory {
            history.record(expansion.snippet, text: expansion.renderedText,
                           appName: lastExternalApp?.localizedName, bundleID: lastExternalApp?.bundleIdentifier)
        }
        playSound()
        OverlayPresenter.shared.play(expansion.style, trigger: expansion.snippet.trigger, text: expansion.renderedText)
    }

    func playSound(named name: String? = nil) {
        guard let name = name ?? soundName, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = Float(soundVolume)
        sound.play()
    }

    /// Types a snippet where you're working, for the search panel and the menu bar's Recent list.
    func insert(_ snippet: Snippet, after delay: TimeInterval = 0.25) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [engine] in
            engine.insert(snippet)
        }
    }

    func setSearchPanelOpen(_ isOpen: Bool) {
        engine.isSuspended = isOpen
    }

    /// The snippet used for previews in Settings.
    var previewSnippet: Snippet {
        store.snippets
            .filter { $0.hasValidTrigger && !$0.expansion.isEmpty && $0.expansion.count <= 40 && !$0.expansion.contains("\n") }
            .max { $0.useCount < $1.useCount }
            ?? Snippet(trigger: "eAD", expansion: "name@example.com")
    }

    // MARK: Snippets and groups

    /// The group a new snippet should go in: the group of the selected snippet, if any.
    private var currentGroupID: SnippetGroup.ID? {
        if case .group(let id) = scope { return id }
        return selectedSnippetIDs.first.flatMap { store.snippet($0)?.groupID }
    }

    /// The Icon and Colour sheet, also the first step of a new snippet or group.
    var appearanceTarget: AppearanceTarget?

    /// Starts a new snippet: the sheet asks for its shortcut, colour and icon, then it opens in the window.
    func newSnippet(in groupID: SnippetGroup.ID?? = nil) {
        appearanceTarget = .newSnippet(groupID ?? currentGroupID)
    }

    /// Starts a new group: the sheet asks for its name, colour and icon.
    func newGroup() {
        appearanceTarget = .newGroup
    }

    /// Dropped snippets move into the group; dropped text from another app becomes a new snippet there.
    @discardableResult
    func handleDrop(_ items: [String], into groupID: SnippetGroup.ID?) -> Bool {
        if items.contains(where: { SnippetDrag.groupID(from: $0) != nil }) { return false }
        let ids = Set(items.flatMap(SnippetDrag.snippetIDs(from:)))
        if !ids.isEmpty {
            store.move(ids, to: groupID)
            if let groupID { store.updateGroup(groupID) { $0.isExpanded = true } }
            return true
        }
        let texts = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return false }
        let created = texts.map { store.add(expansion: $0, groupID: groupID) }
        if let groupID { store.updateGroup(groupID) { $0.isExpanded = true } }
        selection = Set(created.map { .snippet($0.id) })
        return true
    }

    func duplicateSelection() {
        let copies = selectedSnippetIDs.compactMap { store.duplicate($0) }
        if !copies.isEmpty { selection = Set(copies.map { .snippet($0.id) }) }
    }

    func copyExpansion(_ id: Snippet.ID) {
        guard let snippet = store.snippet(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TokenRenderer.render(snippet.expansion).text, forType: .string)
    }

    // MARK: Import and export

    func beginSystemImport() {
        do {
            let entries = try MacReplacementsImporter.loadFromSystem()
            presentImport(entries, source: "macOS Text Replacements")
        } catch {
            alertMessage = ("Couldn't Import Text Replacements", error.localizedDescription)
        }
    }

    /// Imports a Quill backup (.json) or a Text Substitutions plist dragged out of System Settings.
    func importFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "json" {
            do {
                let library = try QuillLibrary.decode(try Data(contentsOf: url))
                let result = store.merge(library)
                var message = "Added \(result.addedSnippets) \(result.addedSnippets == 1 ? "quill" : "quills")"
                if result.addedGroups > 0 { message += " and \(result.addedGroups) \(result.addedGroups == 1 ? "group" : "groups")" }
                message += "."
                if result.skipped > 0 { message += " Skipped \(result.skipped) whose shortcut Quill already has." }
                alertMessage = ("Import Complete", message)
            } catch {
                alertMessage = ("Couldn't Import Quills", "This file isn't a Quill export.")
            }
            return
        }

        do {
            let entries = try MacReplacementsImporter.load(fromFile: url)
            presentImport(entries, source: url.lastPathComponent)
        } catch {
            alertMessage = ("Couldn't Import Text Replacements", error.localizedDescription)
        }
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Quill Library \(SnippetStore.dayKey(for: Date())).json"
        panel.message = "Export every quill and group, to back up or move to another Mac."
        panel.prompt = "Export"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.library.encoded().write(to: url, options: .atomic)
        } catch {
            alertMessage = ("Couldn't Export Quills", error.localizedDescription)
        }
    }

    func showBackups() {
        store.makeDailyBackup()
        try? FileManager.default.createDirectory(at: SnippetStore.backupsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(SnippetStore.backupsURL)
    }

    private func presentImport(_ entries: [MacReplacementsImporter.Entry], source: String) {
        guard !entries.isEmpty else {
            alertMessage = ("Nothing to Import", MacReplacementsImporter.Failure.databaseMissing.localizedDescription)
            return
        }
        let candidates = entries.map { entry in
            ImportSession.Candidate(
                shortcut: entry.shortcut,
                phrase: entry.phrase,
                isAlreadyInQuill: store.containsTrigger(entry.shortcut)
            )
        }
        importSession = ImportSession(source: source, candidates: candidates)
    }

    func finishImport(_ chosen: [ImportSession.Candidate]) {
        let snippets = chosen.map { Snippet(trigger: $0.shortcut, expansion: $0.phrase) }
        store.add(contentsOf: snippets)
        selection = Set(snippets.map { .snippet($0.id) })
        importSession = nil
    }

    // MARK: Windows and Dock icon

    var showsMenuBarExtra: Bool {
        defaults.object(forKey: Self.showMenuBarExtraKey) as? Bool ?? true
    }

    func windowAppeared(_ id: String) {
        visibleWindows.insert(id)
        updateActivationPolicy()
    }

    func windowDisappeared(_ id: String) {
        visibleWindows.remove(id)
        updateActivationPolicy()
    }

    func updateActivationPolicy() {
        let wantsDockIcon = !visibleWindows.isEmpty || !showsMenuBarExtra
        let policy: NSApplication.ActivationPolicy = wantsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Screenshot demos open windows in the background, so they never take your keyboard focus.
        if wantsDockIcon, !CommandLine.arguments.contains("-QuillDemo") { NSApp.activate() }
    }
}

/// A batch of text replacements waiting for the person to choose which to import.
struct ImportSession: Identifiable {
    struct Candidate: Identifiable, Hashable {
        var id: String { shortcut }
        var shortcut: String
        var phrase: String
        var isAlreadyInQuill: Bool
    }

    let id = UUID()
    let source: String
    let candidates: [Candidate]
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
