import Foundation
import SQLite3

/// Reads the text replacements set up in System Settings › Keyboard › Text Replacements.
enum MacReplacementsImporter {
    struct Entry: Hashable {
        var shortcut: String
        var phrase: String
    }

    enum Failure: LocalizedError {
        case databaseMissing
        case databaseUnreadable(String)
        case fileUnreadable

        var errorDescription: String? {
            switch self {
            case .databaseMissing:
                "Quill couldn't find any text replacements on this Mac."
            case .databaseUnreadable(let detail):
                "Quill couldn't read your text replacements (\(detail))."
            case .fileUnreadable:
                "This file doesn't contain text replacements. Drag replacements out of System Settings to export them, then choose that file."
            }
        }
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/KeyboardServices/TextReplacements.db", directoryHint: .notDirectory)
    }

    /// Reads replacements straight from the macOS keyboard database.
    static func loadFromSystem() throws -> [Entry] {
        let path = databaseURL.path
        guard FileManager.default.fileExists(atPath: path) else { throw Failure.databaseMissing }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw Failure.databaseUnreadable(message)
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY
            WHERE ZWASDELETED IS NULL OR ZWASDELETED = 0
            ORDER BY ZSHORTCUT COLLATE NOCASE
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.databaseUnreadable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var entries: [Entry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let shortcut = sqlite3_column_text(statement, 0),
                  let phrase = sqlite3_column_text(statement, 1) else { continue }
            entries.append(Entry(shortcut: String(cString: shortcut), phrase: String(cString: phrase)))
        }
        return unique(entries)
    }

    /// Reads a "Text Substitutions.plist" made by dragging replacements out of System Settings.
    static func load(fromFile url: URL) throws -> [Entry] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let list = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw Failure.fileUnreadable
        }
        let entries = list.compactMap { item -> Entry? in
            guard let shortcut = item["shortcut"] as? String, let phrase = item["phrase"] as? String else { return nil }
            return Entry(shortcut: shortcut, phrase: phrase)
        }
        guard !entries.isEmpty else { throw Failure.fileUnreadable }
        return unique(entries)
    }

    private static func unique(_ entries: [Entry]) -> [Entry] {
        var seen = Set<String>()
        return entries.filter { !$0.shortcut.isEmpty && seen.insert($0.shortcut).inserted }
    }
}
