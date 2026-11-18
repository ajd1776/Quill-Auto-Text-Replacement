import XCTest
@testable import Quill

final class StatsTests: XCTestCase {
    private let calendar = Calendar.current
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15))! }

    private func key(_ daysAgo: Int) -> String {
        SnippetStore.dayKey(for: calendar.date(byAdding: .day, value: -daysAgo, to: today)!)
    }

    private func entry(_ trigger: String, id: UUID = UUID(), daysAgo: Int = 0, hour: Int = 10, app: String? = "Mail", bundle: String? = "com.apple.mail") -> HistoryEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return HistoryEntry(date: date, snippetID: id, trigger: trigger, text: "text for \(trigger)", appName: app, bundleID: bundle)
    }

    func testDaysEndTodayOldestFirst() {
        let days = QuillStats.days(7, from: [key(0): 3, key(6): 1, key(7): 9], today: today)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.uses, 1)
        XCTAssertEqual(days.last?.uses, 3)
        XCTAssertTrue(calendar.isDate(days.last!.date, inSameDayAs: today))
        XCTAssertEqual(days.reduce(0) { $0 + $1.uses }, 4, "Day 7 is outside a 7-day window")
    }

    func testDaysWithZeroCount() {
        XCTAssertTrue(QuillStats.days(0, from: [key(0): 1], today: today).isEmpty)
    }

    func testStreakCountsBackFromToday() {
        XCTAssertEqual(QuillStats.streak([key(0): 1, key(1): 2, key(2): 1, key(4): 5], today: today), 3)
    }

    func testStreakSurvivesAQuietToday() {
        XCTAssertEqual(QuillStats.streak([key(1): 2, key(2): 1], today: today), 2)
    }

    func testStreakIsZeroWithNoRecentUse() {
        XCTAssertEqual(QuillStats.streak([key(3): 2], today: today), 0)
        XCTAssertEqual(QuillStats.streak([:], today: today), 0)
    }

    func testBestDay() {
        XCTAssertEqual(QuillStats.bestDay([key(0): 3, key(5): 11]), 11)
        XCTAssertEqual(QuillStats.bestDay([:]), 0)
    }

    func testHoursHistogram() {
        let hours = QuillStats.hours([entry("a", hour: 9), entry("b", hour: 9), entry("c", hour: 23)], calendar: calendar)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[9], 2)
        XCTAssertEqual(hours[23], 1)
        XCTAssertEqual(hours.reduce(0, +), 3)
    }

    func testTopAppsSortedAndLimited() {
        let entries = [
            entry("a", app: "Mail", bundle: "com.apple.mail"),
            entry("b", app: "Notes", bundle: "com.apple.Notes"),
            entry("c", app: "Notes", bundle: "com.apple.Notes"),
            entry("d", app: nil, bundle: nil),
        ]
        let apps = QuillStats.topApps(entries, limit: 1)
        XCTAssertEqual(apps.map(\.name), ["Notes"])
        XCTAssertEqual(apps.first?.uses, 2)
        XCTAssertEqual(QuillStats.topApps(entries).count, 2, "Entries without an app are left out")
    }

    func testPerSnippetDays() {
        let id = UUID()
        let entries = [entry("eml", id: id, daysAgo: 0), entry("eml", id: id, daysAgo: 0), entry("eml", id: id, daysAgo: 2), entry("sig", daysAgo: 0)]
        let days = QuillStats.days(3, for: id, in: entries, today: today, calendar: calendar)
        XCTAssertEqual(days.map(\.uses), [1, 0, 2])
    }

    func testUnusedSnippets() {
        var old = Snippet(trigger: "old", expansion: "x")
        old.created = today.addingTimeInterval(-30 * 86_400)
        var used = old
        used.trigger = "used"
        used.useCount = 2
        var fresh = Snippet(trigger: "new", expansion: "x")
        fresh.created = today
        var blank = old
        blank.trigger = ""
        XCTAssertEqual(QuillStats.unused([old, used, fresh, blank], now: today).map(\.trigger), ["old"])
    }

    func testTimeSaved() {
        XCTAssertEqual(QuillStats.timeSaved(keys: 200), 60, accuracy: 0.001)
        XCTAssertEqual(QuillStats.durationText(30), "30 sec")
        XCTAssertEqual(QuillStats.durationText(600), "10 min")
        XCTAssertEqual(QuillStats.durationText(5400), "1.5 hr")
    }

    func testHistoryFilter() {
        let id = UUID()
        let entries = [entry("eml", id: id), entry("sig", app: "Notes", bundle: "com.apple.Notes"), entry("thx", app: nil, bundle: nil)]
        XCTAssertEqual(HistoryFilter().apply(to: entries).count, 3)
        XCTAssertFalse(HistoryFilter().isActive)
        XCTAssertEqual(HistoryFilter(query: "SIG").apply(to: entries).map(\.trigger), ["sig"])
        XCTAssertEqual(HistoryFilter(query: "text for t").apply(to: entries).map(\.trigger), ["thx"])
        XCTAssertEqual(HistoryFilter(query: "notes").apply(to: entries).map(\.trigger), ["sig"])
        XCTAssertEqual(HistoryFilter(bundleID: "com.apple.mail").apply(to: entries).map(\.trigger), ["eml"])
        XCTAssertEqual(HistoryFilter(snippetID: id).apply(to: entries).map(\.trigger), ["eml"])
        XCTAssertTrue(HistoryFilter(query: " x ").isActive)
        XCTAssertFalse(HistoryFilter(query: "   ").isActive)
    }
}
