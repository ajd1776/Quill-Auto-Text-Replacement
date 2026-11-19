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
        app.launchArguments = ["-QuillDemoData", "-QuillDemo", demo, "-hasCompletedWelcome", "YES",
                               "-ungroupedExpanded", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "The window should open")
    }

    /// A text by its exact content (SwiftUI puts it in the value or the label on macOS).
    private func text(_ string: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", string, string)).firstMatch
    }

    private var sidebar: XCUIElement { app.outlines.firstMatch }

    private func row(_ trigger: String) -> XCUIElement {
        sidebar.staticTexts[trigger].firstMatch
    }

    func testStatsAndHistoryInSidebar() {
        launch()
        let history = row("History")
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.click()
        XCTAssertTrue(app.searchFields["Search History"].waitForExistence(timeout: 5), "History should show")
        row("Stats").click()
        XCTAssertTrue(app.radioButtons["30 Days"].waitForExistence(timeout: 5), "Stats should show")
    }

    func testKeyboardShortcuts() {
        launch()
        XCTAssertTrue(row("eml").waitForExistence(timeout: 5))
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.searchFields["Search History"].waitForExistence(timeout: 5))
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(app.radioButtons["30 Days"].waitForExistence(timeout: 5))
    }

    func testSelectingASnippetOpensTheEditor() {
        launch()
        let eml = row("eml")
        XCTAssertTrue(eml.waitForExistence(timeout: 5))
        eml.click()
        let field = app.textFields["Shortcut"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The editor should open")
        XCTAssertEqual(field.value as? String, "eml")
        XCTAssertTrue(app.buttons["Delete Snippet"].exists)
    }

    func testNewSnippet() {
        launch()
        app.typeKey("n", modifierFlags: .command)
        let field = app.textFields["Shortcut"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("zzq")
        XCTAssertTrue(row("zzq").waitForExistence(timeout: 5), "The new shortcut should appear in the sidebar")
    }

    func testRowSwitchTurnsSnippetOff() {
        launch()
        XCTAssertTrue(row("eml").waitForExistence(timeout: 5))
        let toggle = sidebar.checkBoxes["Turn eml on or off"].firstMatch
        XCTAssertTrue(toggle.exists, "Each snippet row has its own switch")
        XCTAssertEqual(toggle.value as? Int, 1)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 0, "Clicking the switch turns the snippet off")
    }

    /// A group's header in the sidebar. macOS reads it as one element, so its arrow and switch are clicked by position.
    private func header(_ group: String) -> XCUIElement {
        sidebar.descendants(matching: .any)["group-header-\(group)"].firstMatch
    }

    func testGroupCollapsesAndExpands() {
        launch()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5))
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5), "The Shop header is in the sidebar")
        XCTAssertTrue((shop.value as? String)?.contains("expanded") == true)
        // The dropdown arrow is at the leading edge of the header.
        shop.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 12, dy: 0)).click()
        XCTAssertFalse(row("thx").waitForExistence(timeout: 2), "Collapsing Shop hides its snippets")
        shop.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 12, dy: 0)).click()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5), "Expanding Shop shows them again")
    }

    func testGroupSwitch() {
        launch()
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        XCTAssertTrue((shop.value as? String)?.contains(", on,") == true)
        // The switch is at the trailing edge of the header.
        shop.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -22, dy: 0)).click()
        let off = NSPredicate(format: "value CONTAINS ', off,'")
        expectation(for: off, evaluatedWith: shop)
        waitForExpectations(timeout: 5)
    }

    func testSeveralSelected() {
        launch()
        let eml = row("eml")
        XCTAssertTrue(eml.waitForExistence(timeout: 5))
        eml.click()
        XCUIElement.perform(withKeyModifiers: .command) { row("sig").click() }
        let off = app.buttons["Turn Off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 5), "Two selected snippets show actions for both")
        off.click()
        XCTAssertEqual(sidebar.checkBoxes["Turn eml on or off"].value as? Int, 0)
        XCTAssertEqual(sidebar.checkBoxes["Turn sig on or off"].value as? Int, 0)
    }

    func testSearch() {
        launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("console")
        XCTAssertTrue(row("clog").waitForExistence(timeout: 5))
        XCTAssertFalse(row("eml").exists, "Searching hides snippets that don't match")
    }

    func testSettingsWindow() {
        launch()
        app.typeKey(",", modifierFlags: .command)
        let general = app.toolbars.buttons["General"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 5), "Settings opens in its own window")
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
        next.click()
        XCTAssertTrue(text("You're Ready").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Quill"].exists)
    }
}
