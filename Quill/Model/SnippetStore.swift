import Foundation
import Observation
import SwiftUI

/// Everything Quill saves, in one JSON file. Also the format for export and backups.
struct QuillLibrary: Codable {
    var version = 2
    var snippets: [Snippet] = []
    var groups: [SnippetGroup] = []
    /// Expansions per day, keyed "yyyy-MM-dd".
    var dailyUses: [String: Int] = [:]

    enum CodingKeys: String, CodingKey { case version, snippets, groups, dailyUses }

    init(snippets: [Snippet] = [], groups: [SnippetGroup] = [], dailyUses: [String: Int] = [:]) {
        self.snippets = snippets
        self.groups = groups
        self.dailyUses = dailyUses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        snippets = try container.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
        groups = try container.decodeIfPresent([SnippetGroup].self, forKey: .groups) ?? []
        dailyUses = try container.decodeIfPresent([String: Int].self, forKey: .dailyUses) ?? [:]
    }

    static func decode(_ data: Data) throws -> QuillLibrary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let library = try? decoder.decode(QuillLibrary.self, from: data) { return library }
        // Quill 1.0 saved a bare array of snippets.
        return QuillLibrary(snippets: try decoder.decode([Snippet].self, from: data))
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// Holds every snippet and group and saves them to Application Support.
@MainActor
@Observable
final class SnippetStore {
    var snippets: [Snippet] = [] {
        didSet {
            triggerCounts = Dictionary(snippets.map { ($0.trigger, 1) }, uniquingKeysWith: +)
            changed()
        }
    }
    /// How many quills use each shortcut, kept up to date so the duplicate check is a lookup.
    @ObservationIgnored private var triggerCounts: [String: Int] = [:]
    var groups: [SnippetGroup] = [] {
        didSet { changed() }
    }
    private(set) var dailyUses: [String: Int] = [:] {
        didSet { changed() }
    }

    /// Called whenever snippets or groups change, so the engine can refresh.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false

    static let folderURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Quill", directoryHint: .isDirectory)
    static let fileURL = folderURL.appending(path: "snippets.json", directoryHint: .notDirectory)
    static let backupsURL = folderURL.appending(path: "Backups", directoryHint: .isDirectory)

    init() {
        load()
    }

    private func changed() {
        guard !isLoading else { return }
        onChange?()
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        #if DEBUG
        // Screenshots use made-up snippets held in memory, never saved over the real file.
        if DemoLibrary.isActive {
            isLoading = true
            let demo = DemoLibrary.make()
            snippets = demo.snippets
            groups = demo.groups
            dailyUses = demo.dailyUses
            isLoading = false
            isSaveBlocked = true
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            // The file is there but can't be opened: don't risk replacing it with an empty library.
            isSaveBlocked = true
            loadFailure = "Quill couldn't open its quills file, so it won't save changes until you restart it. Check the file in Settings › Backup."
            quillLog.error("Store: snippets.json exists but couldn't be opened")
            return
        }
        do {
            let library = try QuillLibrary.decode(data)
            snippets = library.snippets
            groups = library.groups
            dailyUses = library.dailyUses
        } catch {
            // Never overwrite a file Quill can't read: set it aside so nothing is lost.
            let aside = Self.folderURL.appending(path: "snippets (unreadable \(Self.dayKey(for: Date()))).json", directoryHint: .notDirectory)
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: Self.fileURL, to: aside)
            loadFailure = "Quill couldn't read its quills file, so it moved it aside as \u{201C}\(aside.lastPathComponent)\u{201D} and started fresh. Your daily backups are in the Backups folder."
            quillLog.error("Store: couldn't read snippets.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Set when the snippets file couldn't be read at launch, so the library can explain.
    var loadFailure: String?
    @ObservationIgnored private var isSaveBlocked = false

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    var library: QuillLibrary {
        QuillLibrary(snippets: snippets, groups: groups, dailyUses: dailyUses)
    }

    func save() {
        guard !isSaveBlocked else { return }
        saveTask?.cancel()
        do {
            try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
            try library.encoded().write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Quill: couldn't save snippets: \(error)")
        }
    }

    /// Keeps one backup per day and the seven most recent.
    func makeDailyBackup() {
        guard !isSaveBlocked else { return }
        let fileManager = FileManager.default
        let name = "Quill \(Self.dayKey(for: Date())).json"
        let url = Self.backupsURL.appending(path: name, directoryHint: .notDirectory)
        guard !snippets.isEmpty, !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: Self.backupsURL, withIntermediateDirectories: true)
            try library.encoded().write(to: url, options: .atomic)
            let backups = try fileManager.contentsOfDirectory(at: Self.backupsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in backups.dropFirst(7) { try? fileManager.removeItem(at: old) }
        } catch {
            NSLog("Quill: couldn't back up snippets: \(error)")
        }
    }

    // MARK: Snippets

    @discardableResult
    func add(trigger: String = "", expansion: String = "", groupID: SnippetGroup.ID? = nil) -> Snippet {
        var snippet = Snippet(trigger: trigger, expansion: expansion)
        snippet.groupID = groupID
        snippets.append(snippet)
        return snippet
    }

    func add(contentsOf new: [Snippet]) {
        snippets.append(contentsOf: new)
    }

    @discardableResult
    func duplicate(_ id: Snippet.ID) -> Snippet? {
        guard let original = snippet(id) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.trigger = uniqueTrigger(from: original.trigger)
        copy.useCount = 0
        copy.lastUsed = nil
        copy.created = Date()
        snippets.append(copy)
        return copy
    }

    private func uniqueTrigger(from base: String) -> String {
        var candidate = base + "2"
        var number = 2
        while containsTrigger(candidate) {
            number += 1
            candidate = base + "\(number)"
        }
        return candidate
    }

    func snippet(_ id: Snippet.ID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    func update(_ id: Snippet.ID, _ change: (inout Snippet) -> Void) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        change(&snippets[index])
    }

    func delete(_ ids: Set<Snippet.ID>, undoManager: UndoManager?) {
        let removed = snippets.enumerated().filter { ids.contains($0.element.id) }
        guard !removed.isEmpty else { return }
        snippets.removeAll { ids.contains($0.id) }
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                for (offset, snippet) in removed {
                    store.snippets.insert(snippet, at: min(offset, store.snippets.count))
                }
            }
        }
        undoManager?.setActionName(removed.count == 1 ? "Delete Quill" : "Delete Quills")
    }

    func setEnabled(_ id: Snippet.ID, _ isEnabled: Bool) {
        update(id) { $0.isEnabled = isEnabled }
    }

    func enabledBinding(for id: Snippet.ID) -> Binding<Bool> {
        Binding(
            get: { self.snippet(id)?.isEnabled ?? false },
            set: { self.setEnabled(id, $0) }
        )
    }

    /// Puts snippets just before another snippet (or at the end of a group when `target` is nil),
    /// moving them into that snippet's group. Keeps their order relative to each other.
    func move(_ ids: Set<Snippet.ID>, before target: Snippet.ID?, in groupID: SnippetGroup.ID?) {
        guard !ids.isEmpty, target.map({ !ids.contains($0) }) ?? true else { return }
        var moving = snippets.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        let destinationGroup = target.flatMap(snippet)?.groupID ?? groupID
        for index in moving.indices { moving[index].groupID = destinationGroup }
        var rest = snippets.filter { !ids.contains($0.id) }
        let insertAt: Int
        if let target, let index = rest.firstIndex(where: { $0.id == target }) {
            insertAt = index
        } else if let last = rest.lastIndex(where: { $0.groupID == destinationGroup }) {
            insertAt = last + 1
        } else {
            insertAt = rest.endIndex
        }
        rest.insert(contentsOf: moving, at: insertAt)
        snippets = rest
    }

    /// Puts a group just before another group, or last when `target` is nil.
    func moveGroup(_ id: SnippetGroup.ID, before target: SnippetGroup.ID?) {
        guard id != target, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups.remove(at: index)
        let insertAt = target.flatMap { t in groups.firstIndex { $0.id == t } } ?? groups.endIndex
        groups.insert(group, at: insertAt)
    }

    func move(_ ids: Set<Snippet.ID>, to groupID: SnippetGroup.ID?) {
        for index in snippets.indices where ids.contains(snippets[index].id) {
            snippets[index].groupID = groupID
        }
    }

    func binding(for id: Snippet.ID) -> Binding<Snippet>? {
        guard let current = snippet(id) else { return nil }
        return Binding(
            get: { self.snippet(id) ?? current },
            set: { newValue in
                if let index = self.snippets.firstIndex(where: { $0.id == id }) {
                    self.snippets[index] = newValue
                }
            }
        )
    }

    /// Snippets the engine should match: switched on, valid, and in a group that's on.
    var activeSnippets: [Snippet] {
        let disabledGroups = Set(groups.filter { !$0.isEnabled }.map(\.id))
        return snippets.filter { snippet in
            snippet.isEnabled && snippet.hasValidTrigger && !snippet.expansion.isEmpty
                && !(snippet.groupID.map(disabledGroups.contains) ?? false)
        }
    }

    /// A snippet's colour: its own, else its group's, else the accent colour.
    func tint(for snippet: Snippet) -> Color {
        QuillColor.resolve(snippet.color) ?? group(for: snippet)?.tint ?? .accentColor
    }

    func isActive(_ snippet: Snippet) -> Bool {
        snippet.isEnabled && (snippet.groupID.flatMap(group)?.isEnabled ?? true)
    }

    var recentlyUsed: [Snippet] {
        snippets
            .filter { $0.lastUsed != nil && $0.hasValidTrigger }
            .sorted(by: SnippetSortOrder.recentlyUsed.areInIncreasingOrder)
    }

    // MARK: Groups

    func group(_ id: SnippetGroup.ID) -> SnippetGroup? {
        groups.first { $0.id == id }
    }

    func group(for snippet: Snippet) -> SnippetGroup? {
        snippet.groupID.flatMap(group)
    }

    func snippets(in groupID: SnippetGroup.ID?) -> [Snippet] {
        snippets.filter { $0.groupID == groupID }
    }

    @discardableResult
    func addGroup(named name: String = "New Group") -> SnippetGroup {
        let used = Set(groups.map(\.color))
        let color = GroupColor.allCases.first { !used.contains($0) } ?? .blue
        let group = SnippetGroup(name: uniqueGroupName(name), color: color)
        groups.append(group)
        return group
    }

    private func uniqueGroupName(_ base: String) -> String {
        guard groups.contains(where: { $0.name == base }) else { return base }
        var number = 2
        while groups.contains(where: { $0.name == "\(base) \(number)" }) { number += 1 }
        return "\(base) \(number)"
    }

    func updateGroup(_ id: SnippetGroup.ID, _ change: (inout SnippetGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[index])
    }

    /// Moves a group up (negative) or down (positive) in the sidebar, stopping at either end.
    func moveGroup(_ id: SnippetGroup.ID, by offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), groups.count - 1)
        guard target != index else { return }
        let group = groups.remove(at: index)
        groups.insert(group, at: target)
    }

    func deleteGroup(_ id: SnippetGroup.ID, keepingSnippets: Bool) {
        if keepingSnippets {
            move(Set(snippets(in: id).map(\.id)), to: nil)
        } else {
            snippets.removeAll { $0.groupID == id }
        }
        groups.removeAll { $0.id == id }
    }

    func groupEnabledBinding(for id: SnippetGroup.ID) -> Binding<Bool> {
        Binding(
            get: { self.group(id)?.isEnabled ?? true },
            set: { value in self.updateGroup(id) { $0.isEnabled = value } }
        )
    }

    func groupExpandedBinding(for id: SnippetGroup.ID) -> Binding<Bool> {
        Binding(
            get: { self.group(id)?.isExpanded ?? true },
            set: { value in self.updateGroup(id) { $0.isExpanded = value } }
        )
    }

    // MARK: Usage

    nonisolated static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func recordUse(_ id: Snippet.ID) {
        update(id) {
            $0.useCount += 1
            $0.lastUsed = Date()
        }
        dailyUses[Self.dayKey(for: Date()), default: 0] += 1
    }

    /// Called when an expansion is undone with Delete, so it doesn't count.
    func undoUse(_ id: Snippet.ID) {
        update(id) { $0.useCount = max(0, $0.useCount - 1) }
        let key = Self.dayKey(for: Date())
        dailyUses[key] = max(0, (dailyUses[key] ?? 0) - 1)
    }

    var totalKeysSaved: Int {
        snippets.reduce(0) { $0 + $1.keysSaved }
    }

    var totalUses: Int {
        snippets.reduce(0) { $0 + $1.useCount }
    }

    func uses(onDayOffset offset: Int) -> Int {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return dailyUses[Self.dayKey(for: date)] ?? 0
    }

    // MARK: Import

    struct MergeResult {
        var addedSnippets = 0
        var addedGroups = 0
        var skipped = 0
    }

    /// Adds snippets and groups from another library, skipping shortcuts Quill already has.
    func merge(_ other: QuillLibrary) -> MergeResult {
        var result = MergeResult()
        var groupMap: [SnippetGroup.ID: SnippetGroup.ID] = [:]
        for group in other.groups {
            if let existing = groups.first(where: { $0.name == group.name }) {
                groupMap[group.id] = existing.id
            } else {
                var copy = group
                copy.id = UUID()
                groups.append(copy)
                groupMap[group.id] = copy.id
                result.addedGroups += 1
            }
        }
        var newSnippets: [Snippet] = []
        for snippet in other.snippets {
            if containsTrigger(snippet.trigger) || newSnippets.contains(where: { $0.trigger == snippet.trigger }) {
                result.skipped += 1
                continue
            }
            var copy = snippet
            copy.id = UUID()
            copy.groupID = snippet.groupID.flatMap { groupMap[$0] }
            newSnippets.append(copy)
        }
        snippets.append(contentsOf: newSnippets)
        result.addedSnippets = newSnippets.count
        return result
    }

    // MARK: Validation

    func containsTrigger(_ trigger: String) -> Bool {
        snippets.contains { $0.trigger == trigger }
    }

    /// A short message describing why a snippet's shortcut won't work, or nil if it's fine.
    func problem(with snippet: Snippet) -> String? {
        if snippet.trigger.isEmpty { return "Enter a shortcut to use this quill." }
        if snippet.trigger.contains(where: \.isWhitespace) { return "Shortcuts can't contain spaces." }
        if snippet.expansion.isEmpty { return "Add the text this shortcut expands to." }
        if triggerCounts[snippet.trigger, default: 0] > 1 { return "Another quill already uses this shortcut." }
        return nil
    }
}
