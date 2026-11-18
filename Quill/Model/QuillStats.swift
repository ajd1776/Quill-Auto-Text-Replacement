import Foundation

/// Numbers for the Stats page, the editor's Usage section and the History filters.
/// Pure functions over the library and history, so they're easy to test.
enum QuillStats {
    /// A typical typing speed, used to turn keys saved into time saved.
    static let charactersPerMinute = 200.0

    struct Day: Identifiable, Equatable {
        let date: Date
        let uses: Int
        var id: Date { date }
    }

    struct AppUsage: Identifiable, Equatable {
        let name: String
        let bundleID: String?
        let uses: Int
        var id: String { bundleID ?? name }
    }

    // MARK: Time

    static func timeSaved(keys: Int) -> TimeInterval {
        Double(keys) / (charactersPerMinute / 60)
    }

    /// "45 sec", "12 min", "3.4 hr".
    static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) sec" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return String(format: "%.1f hr", seconds / 3600)
    }

    // MARK: Days

    /// One entry per day, oldest first, ending today.
    static func days(_ count: Int, from dailyUses: [String: Int], today: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let start = calendar.startOfDay(for: today)
        return (0..<max(count, 0)).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
            return Day(date: date, uses: dailyUses[SnippetStore.dayKey(for: date)] ?? 0)
        }
    }

    /// Days in a row with at least one expansion, ending today. A quiet today doesn't break
    /// the streak until the day is over, so it counts back from yesterday instead.
    static func streak(_ dailyUses: [String: Int], today: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if (dailyUses[SnippetStore.dayKey(for: day)] ?? 0) == 0 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while (dailyUses[SnippetStore.dayKey(for: day)] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func bestDay(_ dailyUses: [String: Int]) -> Int {
        dailyUses.values.max() ?? 0
    }

    // MARK: History

    /// Expansions per hour of the day, 0 to 23.
    static func hours(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [Int] {
        var hours = Array(repeating: 0, count: 24)
        for entry in entries {
            hours[calendar.component(.hour, from: entry.date)] += 1
        }
        return hours
    }

    /// Apps by number of expansions, most first. Entries with no app are left out.
    static func topApps(_ entries: [HistoryEntry], limit: Int = 5) -> [AppUsage] {
        var counts: [String: (name: String, bundleID: String?, uses: Int)] = [:]
        for entry in entries {
            guard let name = entry.appName else { continue }
            let key = entry.bundleID ?? name
            counts[key, default: (name, entry.bundleID, 0)].uses += 1
        }
        return counts.values
            .map { AppUsage(name: $0.name, bundleID: $0.bundleID, uses: $0.uses) }
            .sorted { $0.uses != $1.uses ? $0.uses > $1.uses : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }

    /// One snippet's expansions per day from the history, oldest first, ending today.
    static func days(_ count: Int, for snippetID: Snippet.ID, in entries: [HistoryEntry],
                     today: Date = Date(), calendar: Calendar = .current) -> [Day] {
        var byDay: [String: Int] = [:]
        for entry in entries where entry.snippetID == snippetID {
            byDay[SnippetStore.dayKey(for: entry.date), default: 0] += 1
        }
        return days(count, from: byDay, today: today, calendar: calendar)
    }

    // MARK: Tidying up

    /// Snippets never used in the `days` since they were made: candidates to turn off or delete.
    static func unused(_ snippets: [Snippet], olderThan days: Int = 14, now: Date = Date()) -> [Snippet] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return snippets
            .filter { $0.useCount == 0 && $0.created < cutoff && $0.hasValidTrigger }
            .sorted { $0.created < $1.created }
    }
}

/// What the History page shows: search text, an app and a snippet to narrow it down.
struct HistoryFilter: Equatable {
    var query = ""
    var bundleID: String?
    var snippetID: Snippet.ID?

    var isActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || bundleID != nil || snippetID != nil }

    func apply(to entries: [HistoryEntry]) -> [HistoryEntry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            if let bundleID, entry.bundleID != bundleID { return false }
            if let snippetID, entry.snippetID != snippetID { return false }
            guard !text.isEmpty else { return true }
            return entry.trigger.localizedCaseInsensitiveContains(text)
                || entry.text.localizedCaseInsensitiveContains(text)
                || (entry.appName?.localizedCaseInsensitiveContains(text) ?? false)
        }
    }
}
