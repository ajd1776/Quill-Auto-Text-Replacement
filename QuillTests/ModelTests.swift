import SwiftUI
import XCTest
@testable import Quill

final class ModelTests: XCTestCase {
    // MARK: Tokens

    func testPlainTextIsUnchanged() {
        XCTAssertEqual(TokenRenderer.render("hello", clipboard: nil).text, "hello")
        XCTAssertFalse(TokenRenderer.containsTokens("hello"))
    }

    func testInputsAndLabels() {
        let template = "Hi {input:Name}, order {input: Order }, again {input:Name}"
        XCTAssertEqual(TokenRenderer.inputFields(in: template), ["Name", "Order"])
        XCTAssertEqual(TokenRenderer.render(template, inputs: ["Name": "Sam", "Order": "#1"], clipboard: nil).text,
                       "Hi Sam, order #1, again Sam")
        XCTAssertEqual(TokenRenderer.render("{input:Name}", clipboard: nil).text, "Name", "Labels stand in without values")
    }

    func testDateFormatAndClipboard() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        XCTAssertEqual(TokenRenderer.render("{date:yyyy-MM-dd}", now: date, clipboard: nil).text, "2026-03-09")
        XCTAssertEqual(TokenRenderer.render("[{clipboard}]", clipboard: "copied").text, "[copied]")
        XCTAssertEqual(TokenRenderer.render("[{clipboard}]", clipboard: nil).text, "[]")
        XCTAssertTrue(TokenRenderer.containsTokens("{date}"))
    }

    func testCursor() {
        let rendered = TokenRenderer.render("console.log({cursor})", clipboard: nil)
        XCTAssertEqual(rendered.text, "console.log()")
        XCTAssertEqual(rendered.cursorBack, 1)
    }

    // MARK: Case matching

    func testCaseAdapter() {
        XCTAssertEqual(CaseAdapter.adapt("on my way", typed: "omw", trigger: "omw"), "on my way")
        XCTAssertEqual(CaseAdapter.adapt("on my way", typed: "OMW", trigger: "omw"), "ON MY WAY")
        XCTAssertEqual(CaseAdapter.adapt("on my way", typed: "Omw", trigger: "omw"), "On my way")
        XCTAssertEqual(CaseAdapter.adapt("on my way", typed: "oMw", trigger: "omw"), "on my way")
    }

    // MARK: Snippets

    func testSnippetBasics() {
        var snippet = Snippet(trigger: "eml", expansion: "name@example.com")
        XCTAssertTrue(snippet.hasValidTrigger)
        snippet.useCount = 2
        XCTAssertEqual(snippet.keysSaved, (16 - 3) * 2)
        XCTAssertFalse(Snippet(trigger: "a b", expansion: "x").hasValidTrigger)
        XCTAssertEqual(Snippet(trigger: "x", expansion: "a\nb").preview, "a b")
        XCTAssertEqual(Snippet(trigger: "x", expansion: "").preview, "No text")
    }

    func testAppLimits() {
        var snippet = Snippet(trigger: "x", expansion: "y")
        XCTAssertTrue(snippet.isAllowed(in: nil))
        snippet.appBundleIDs = ["com.apple.mail"]
        XCTAssertTrue(snippet.isAllowed(in: "com.apple.mail"))
        XCTAssertFalse(snippet.isAllowed(in: "com.apple.Notes"))
        XCTAssertFalse(snippet.isAllowed(in: nil))
    }

    func testLegacySnippetDecodes() throws {
        let json = #"{"trigger":"eml","expansion":"a@b.c","animation":"somethingNew"}"#
        let snippet = try JSONDecoder().decode(Snippet.self, from: Data(json.utf8))
        XCTAssertEqual(snippet.trigger, "eml")
        XCTAssertNil(snippet.animation, "Unknown effects fall back to the default")
        XCTAssertTrue(snippet.isEnabled)
        XCTAssertEqual(snippet.mode, .afterDelimiter)
        XCTAssertTrue(snippet.appBundleIDs.isEmpty)
    }

    func testLibraryRoundTrip() throws {
        var group = SnippetGroup(name: "Work")
        group.customColor = "#123ABC"
        var snippet = Snippet(trigger: "sig", expansion: "Best")
        snippet.groupID = group.id
        // Saved dates keep whole seconds.
        snippet.created = Date(timeIntervalSince1970: 1_790_000_000)
        let library = QuillLibrary(snippets: [snippet], groups: [group], dailyUses: ["2026-11-18": 4])
        let decoded = try QuillLibrary.decode(try library.encoded())
        XCTAssertEqual(decoded.snippets, [snippet])
        XCTAssertEqual(decoded.groups, [group])
        XCTAssertEqual(decoded.dailyUses["2026-11-18"], 4)
    }

    func testSortOrders() {
        var a = Snippet(trigger: "b", expansion: "x"); a.useCount = 1
        var b = Snippet(trigger: "a", expansion: "x"); b.useCount = 5
        let blank = Snippet(trigger: "", expansion: "")
        XCTAssertEqual([a, b, blank].sorted(by: SnippetSortOrder.shortcut.areInIncreasingOrder).map(\.trigger), ["", "a", "b"])
        XCTAssertEqual([a, b].sorted(by: SnippetSortOrder.mostUsed.areInIncreasingOrder).map(\.trigger), ["a", "b"])
    }

    // MARK: Colours and versions

    func testHexColours() {
        XCTAssertNotNil(Color(hex: "#FF8800"))
        XCTAssertNotNil(Color(hex: "ff8800"))
        XCTAssertNil(Color(hex: "#FF88"))
        XCTAssertNil(Color(hex: "zzzzzz"))
        XCTAssertEqual(Color(hex: "#3366CC")?.hexString, "#3366CC")
        var group = SnippetGroup(name: "G")
        group.customColor = "nonsense"
        XCTAssertEqual(group.tint, group.color.color, "A bad custom colour falls back to the preset")
    }

    @MainActor
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", newerThan: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.1", newerThan: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2", newerThan: "1.3"))
    }

    func testEmojiDetection() {
        XCTAssertTrue(IconKind.isEmoji("🔥"))
        XCTAssertFalse(IconKind.isEmoji("folder.fill"))
        XCTAssertFalse(IconKind.isEmoji("a"))
    }

    @MainActor
    func testMenuBarIconsDraw() {
        for icon in MenuBarIcon.allCases {
            let on = icon.image(isOn: true)
            let off = icon.image(isOn: false)
            XCTAssertTrue(on.isTemplate, "\(icon) should be a template image")
            XCTAssertGreaterThan(on.size.width, 0)
            XCTAssertGreaterThan(off.size.width, 0)
            XCTAssertFalse(icon.title.isEmpty)
        }
    }
}
