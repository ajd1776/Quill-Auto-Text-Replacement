import Foundation
import Observation

/// One expansion: which snippet, what it typed, and where.
struct HistoryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var snippetID: Snippet.ID
    var trigger: String
    /// The typed text, cut to a preview length.
    var text: String
    var appName: String?
    var bundleID: String?
}

/// Recent expansions, kept on this Mac in history.json. Off with Settings › General › Keep expansion history.
@MainActor
@Observable
final class ExpansionHistory {
    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isReadOnly = false
    private let limit = 300
    private let previewLength = 200

    static let fileURL = SnippetStore.folderURL.appending(path: "history.json", directoryHint: .notDirectory)

    init() {
        #if DEBUG
        if DemoLibrary.isActive {
            entries = DemoLibrary.history()
            isReadOnly = true
            return
        }
        #endif
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    func record(_ snippet: Snippet, text: String, appName: String?, bundleID: String?) {
        let preview = text.count > previewLength ? String(text.prefix(previewLength)) + "…" : text
        entries.insert(HistoryEntry(date: Date(), snippetID: snippet.id, trigger: snippet.trigger,
                                    text: preview, appName: appName, bundleID: bundleID), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        scheduleSave()
    }

    /// Undoing an expansion with Delete removes its entry too.
    func removeLatest(for snippetID: Snippet.ID) {
        guard let index = entries.firstIndex(where: { $0.snippetID == snippetID }), index < 3 else { return }
        entries.remove(at: index)
        scheduleSave()
    }

    func remove(_ ids: Set<HistoryEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    private func scheduleSave() {
        guard !isReadOnly else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        guard !isReadOnly else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: SnippetStore.folderURL, withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: Self.fileURL, options: .atomic)
        } catch {
            quillLog.error("History: couldn't save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
