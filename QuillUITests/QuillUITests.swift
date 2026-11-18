import XCTest

/// Clicks through Quill's window with the in-memory demo library (never the real one).
final class QuillUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
    }

    private func launch(_ demo: String = "library", _ extra: [String] = []) {
        app.launchArguments = ["-QuillDemoData", "-QuillDemo", demo, "-hasCompletedWelcome", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "The window should open")
    }

    /// The toolbar tabs are a segmented control: radio buttons on macOS.
    private func openPage(_ title: String) {
        let tab = app.radioButtons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab \(title) should exist")
        tab.click()
    }

    /// A text by its exact content (SwiftUI puts it in the value on macOS, which the subscript matches).
    private func text(_ string: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", string, string)).firstMatch
    }

    /// An element by accessibility identifier, whatever kind it turns out to be.
    private func element(_ id: String) -> XCUIElement {
        for query in [app.groups, app.otherElements, app.buttons, app.cells, app.staticTexts] where query[id].exists {
            return query[id].firstMatch
        }
        return app.groups[id].firstMatch
    }

    private func waitFor(_ id: String, timeout: TimeInterval = 5) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let found = element(id)
            if found.exists { return found }
            usleep(250_000)
        } while Date() < end
        return nil
    }

    private func row(_ trigger: String) -> XCUIElement {
        app.outlines.staticTexts[trigger].firstMatch.exists
            ? app.outlines.staticTexts[trigger].firstMatch
            : app.tables.staticTexts[trigger].firstMatch
    }

    func testEveryPageOpens() {
        launch()
        openPage("Stats")
        XCTAssertTrue(text("Expansions per Day").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Busiest Hours").exists)
        XCTAssertTrue(text("Top Apps").exists)
        openPage("History")
        XCTAssertTrue(app.searchFields["Search History"].waitForExistence(timeout: 5) || text("History").waitForExistence(timeout: 5))
        openPage("Settings")
        // Settings reopens on the last pane used, so pick General first.
        let general = app.outlines.staticTexts["General"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.click()
        XCTAssertTrue(text("Launch at login").waitForExistence(timeout: 5), "General settings should show")
        openPage("Snippets")
        XCTAssertTrue(text("All Snippets").waitForExistence(timeout: 5))
    }

    func testKeyboardShortcutsSwitchPages() {
        launch()
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(text("Expansions per Day").waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.searchFields["Search History"].waitForExistence(timeout: 5) || text("History").waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(text("All Snippets").waitForExistence(timeout: 5))
    }

    func testSelectingASnippetOpensTheEditor() {
        launch()
        let eml = row("eml")
        XCTAssertTrue(eml.waitForExistence(timeout: 5))
        eml.click()
        let field = app.textFields["shortcut-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The editor should open")
        XCTAssertEqual(field.value as? String, "eml")
        XCTAssertTrue(text("Expands").exists, "The Behaviour section should show")
        XCTAssertTrue(text("Works In").exists, "The Apps section should show")
    }

    func testNewSnippet() {
        launch()
        app.typeKey("n", modifierFlags: .command)
        let field = app.textFields["shortcut-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("zzq")
        XCTAssertTrue(row("zzq").waitForExistence(timeout: 5), "The new shortcut should appear in the list")
    }

    func testBulkActionsBar() {
        launch()
        let eml = row("eml")
        XCTAssertTrue(eml.waitForExistence(timeout: 5))
        eml.click()
        XCUIElement.perform(withKeyModifiers: .command) { row("sig").click() }
        let off = app.buttons["bulk-off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 5), "Selecting two snippets should show the bulk bar")
        XCTAssertTrue(text("2 Selected").exists)
        off.click()
        app.links["bulk-clear"].firstMatch.click()
        XCTAssertFalse(text("2 Selected").waitForExistence(timeout: 2))
        // Both are now off, so the Off filter lists them.
        app.outlines.staticTexts["Off"].firstMatch.click()
        XCTAssertTrue(row("eml").waitForExistence(timeout: 5))
        XCTAssertTrue(row("sig").exists)
    }

    func testGridView() {
        launch("grid")
        guard let card = waitFor("card-eml") else { return XCTFail("The eml card should show") }
        card.click()
        XCTAssertTrue(app.textFields["shortcut-field"].waitForExistence(timeout: 5), "Clicking a card opens the editor")
    }

    func testGroupFilter() {
        launch()
        let shop = app.outlines.staticTexts["Shop"].firstMatch
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        shop.click()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5))
        XCTAssertFalse(row("eml").exists, "Personal snippets aren't in Shop")
    }

    func testHistorySearch() {
        launch("history")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        let rowsBefore = app.outlines.firstMatch.outlineRows.count
        search.typeText("console")
        let filtered = NSPredicate(format: "count < %d AND count > 0", rowsBefore)
        expectation(for: filtered, evaluatedWith: app.outlines.firstMatch.outlineRows)
        waitForExpectations(timeout: 5)
    }

    func testStatsPeriod() {
        launch("stats")
        for days in [7, 30, 14] {
            let button = app.radioButtons["\(days) Days"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()
            XCTAssertTrue(text("Last \(days) days").waitForExistence(timeout: 5), "The chart should cover \(days) days")
        }
    }

    func testAboutPane() {
        launch("about")
        let link = app.links["Source Code on GitHub"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5) || app.buttons["Source Code on GitHub"].exists)
        XCTAssertTrue(text("Version 1.2").exists || app.staticTexts.containing(NSPredicate(format: "value BEGINSWITH 'Version'")).firstMatch.exists)
    }

    func testWelcomeTour() {
        app.launchArguments = ["-QuillDemoData", "-QuillDemo", "welcome", "-hasCompletedWelcome", "NO"]
        app.launch()
        XCTAssertTrue(text("Welcome to Quill").waitForExistence(timeout: 10))
        let next = app.buttons["Continue"].firstMatch
        next.click()
        XCTAssertTrue(text("Allow Accessibility Access").waitForExistence(timeout: 5))
        next.click()
        XCTAssertTrue(text("Bring In Your Snippets").waitForExistence(timeout: 5))
        app.buttons["Import"].firstMatch.click()
        XCTAssertTrue(text("Added 1 snippet").waitForExistence(timeout: 5)
                      || text("Already in Quill").exists, "Import should report what it added")
        next.click()
        XCTAssertTrue(text("You're Ready").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Quill"].exists)
    }
}
