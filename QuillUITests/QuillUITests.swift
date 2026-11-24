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

    func testTabBar() {
        launch()
        let history = app.buttons["tab-history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.click()
        XCTAssertTrue(app.searchFields["Search History"].waitForExistence(timeout: 5), "History should show")
        app.buttons["tab-stats"].firstMatch.click()
        XCTAssertTrue(app.radioButtons["30 Days"].waitForExistence(timeout: 5), "Stats should show")
        app.buttons["tab-snippets"].firstMatch.click()
        XCTAssertTrue(row("eml").waitForExistence(timeout: 5), "Quills should show the sidebar")
        app.buttons["tab-new"].firstMatch.click()
        XCTAssertTrue(app.textFields["appearance-name"].firstMatch.waitForExistence(timeout: 5), "New opens Icon and Colour")
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
        XCTAssertTrue(app.buttons["Delete Quill"].exists)
    }

    func testNewSnippet() {
        launch()
        app.typeKey("n", modifierFlags: .command)
        let name = app.textFields["appearance-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "New Snippet opens the icon and colour sheet first")
        XCTAssertFalse(app.buttons["Create"].isEnabled, "Create waits for a shortcut")
        name.click()
        name.typeText("zzq")
        app.buttons["Create"].click()
        let field = app.textFields["Shortcut"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The new snippet opens in the editor")
        XCTAssertEqual(field.value as? String, "zzq")
        XCTAssertTrue(row("zzq").exists, "It appears in the sidebar")
    }

    func testIconOpensAppearanceSheet() {
        launch()
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        shop.rightClick()
        app.menuItems["Icon and Colour…"].firstMatch.click()
        let name = app.textFields["appearance-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Shop")
        app.buttons["Purple"].firstMatch.click()
        app.buttons["Save"].click()
        XCTAssertFalse(name.waitForExistence(timeout: 2), "Saving closes the sheet")
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
        sidebar.descendants(matching: .any).matching(identifier: "group-header-\(group)").firstMatch
    }

    func testGroupCollapsesAndExpands() {
        launch()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5))
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5), "The Shop header is in the sidebar")
        XCTAssertTrue((shop.value as? String)?.contains("expanded") == true)
        shop.rightClick()
        app.menuItems["Collapse Group"].firstMatch.click()
        XCTAssertFalse(row("thx").waitForExistence(timeout: 2), "Collapsing Shop hides its snippets")
        XCTAssertTrue((shop.value as? String)?.contains("collapsed") == true)
        shop.rightClick()
        app.menuItems["Expand Group"].firstMatch.click()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5), "Expanding Shop shows them again")
    }

    func testClickingGroupHeaderCollapses() {
        launch()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5))
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        // Click the middle of the header, away from its buttons and switch.
        shop.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).click()
        XCTAssertFalse(row("thx").waitForExistence(timeout: 2), "Clicking the header collapses the group")
        shop.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).click()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5), "Clicking again expands it")
    }

    func testClickingGroupIconDoesNotCollapse() {
        launch()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 5))
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        // The icon square is at the leading edge of the header.
        shop.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 14, dy: 0)).click()
        let name = app.textFields["appearance-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Clicking the icon opens Icon and Colour")
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 3), "…and doesn't collapse the group")
    }

    func testDoubleClickOpensIconAndColour() {
        launch()
        let eml = row("eml")
        XCTAssertTrue(eml.waitForExistence(timeout: 5))
        eml.doubleClick()
        let name = app.textFields["appearance-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Double-clicking a snippet opens Icon and Colour")
        XCTAssertEqual(name.value as? String, "eml")
        app.buttons["Cancel"].firstMatch.click()

        let shop = header("Shop")
        shop.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).doubleClick()
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Double-clicking a group opens Icon and Colour")
        XCTAssertEqual(name.value as? String, "Shop")
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(row("thx").waitForExistence(timeout: 3), "Double-clicking doesn't collapse the group")
    }

    func testDragToReorder() {
        launch()
        let eml = row("eml"), addr = row("addr")
        XCTAssertTrue(eml.waitForExistence(timeout: 5))
        // Drag whichever is lower onto the one above it; it should land above.
        let (lower, upper, lowerName, upperName) = eml.frame.minY > addr.frame.minY
            ? (eml, addr, "eml", "addr") : (addr, eml, "addr", "eml")
        lower.press(forDuration: 0.6, thenDragTo: upper)
        let moved = NSPredicate { _, _ in self.row(lowerName).frame.minY < self.row(upperName).frame.minY }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    func testGroupSwitch() {
        launch()
        let shop = header("Shop")
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        XCTAssertTrue((shop.value as? String)?.contains(", on,") == true)
        shop.rightClick()
        app.menuItems["Turn Group Off"].firstMatch.click()
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
        for trigger in ["eml", "sig"] {
            expectation(for: NSPredicate(format: "value == 0"), evaluatedWith: sidebar.checkBoxes["Turn \(trigger) on or off"])
        }
        waitForExpectations(timeout: 5)
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

    func testSettingsPage() {
        launch()
        app.typeKey(",", modifierFlags: .command)
        let general = app.buttons["settings-tab-general"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 5), "Settings opens as a page in the main window")
        app.buttons["settings-tab-effects"].firstMatch.click()
        XCTAssertTrue(text("Effect").waitForExistence(timeout: 5) || app.popUpButtons.firstMatch.exists)
    }

    func testFiringRange() {
        launch()
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.textViews["range-practice"].firstMatch.waitForExistence(timeout: 5), "⌘R opens the Firing Range")
        XCTAssertTrue(app.textViews["range-practice"].firstMatch.exists)
    }

    func testWelcomeTour() {
        app.launchArguments = ["-QuillDemoData", "-QuillDemo", "welcome", "-hasCompletedWelcome", "NO"]
        app.launch()
        XCTAssertTrue(text("Welcome to Quill").waitForExistence(timeout: 10))
        let next = app.buttons["Continue"].firstMatch
        next.click()
        XCTAssertTrue(text("Allow Accessibility Access").waitForExistence(timeout: 5))
        next.click()
        XCTAssertTrue(text("Bring In Your Quills").waitForExistence(timeout: 5))
        next.click()
        XCTAssertTrue(text("You're Ready").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Quill"].exists)
    }
}
