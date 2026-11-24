import XCTest
@testable import Quill

/// Each test gets its own store, loaded from the in-memory demo library and never saved.
@MainActor
final class StoreTests: XCTestCase {
    private var store: SnippetStore!

    override func setUp() async throws {
        store = SnippetStore()
    }

    func testDemoLibraryLoads() {
        XCTAssertTrue(DemoLibrary.isActive)
        XCTAssertGreaterThanOrEqual(store.snippets.count, 10)
        XCTAssertEqual(store.groups.count, 3)
    }

    func testAddDuplicateDelete() {
        let count = store.snippets.count
        let added = store.add(trigger: "zz", expansion: "zed")
        XCTAssertEqual(store.snippets.count, count + 1)
        let copy = store.duplicate(added.id)
        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy?.id, added.id)
        store.delete([added.id, copy!.id], undoManager: nil)
        XCTAssertEqual(store.snippets.count, count)
        XCTAssertNil(store.snippet(added.id))
    }

    func testProblems() {
        let blank = store.add()
        XCTAssertNotNil(store.problem(with: blank))
        let spaced = store.add(trigger: "a b", expansion: "x")
        XCTAssertEqual(store.problem(with: spaced), "Shortcuts can't contain spaces.")
        let empty = store.add(trigger: "solo", expansion: "")
        XCTAssertEqual(store.problem(with: empty), "Add the text this shortcut expands to.")
        let twin = store.add(trigger: "eml", expansion: "other")
        XCTAssertEqual(store.problem(with: twin), "Another quill already uses this shortcut.")
        let fine = store.add(trigger: "fine", expansion: "ok")
        XCTAssertNil(store.problem(with: fine))
    }

    func testGroupsControlActiveSnippets() throws {
        let group = store.addGroup(named: "Temp")
        let snippet = store.add(trigger: "tmp", expansion: "temporary", groupID: group.id)
        XCTAssertTrue(store.isActive(snippet))
        store.updateGroup(group.id) { $0.isEnabled = false }
        XCTAssertFalse(store.isActive(store.snippet(snippet.id)!))
        XCTAssertFalse(store.activeSnippets.contains { $0.id == snippet.id })
        store.setEnabled(snippet.id, false)
        store.updateGroup(group.id) { $0.isEnabled = true }
        XCTAssertFalse(store.isActive(store.snippet(snippet.id)!), "The snippet's own switch still counts")
    }

    func testMoveAndDeleteGroup() {
        let group = store.addGroup(named: "Moving")
        let snippet = store.add(trigger: "mv", expansion: "move me")
        store.move([snippet.id], to: group.id)
        XCTAssertEqual(store.snippet(snippet.id)?.groupID, group.id)
        store.deleteGroup(group.id, keepingSnippets: true)
        XCTAssertNil(store.group(group.id))
        XCTAssertNil(store.snippet(snippet.id)?.groupID)
        XCTAssertNotNil(store.snippet(snippet.id))

        let other = store.addGroup(named: "Gone")
        let inside = store.add(trigger: "gone", expansion: "x", groupID: other.id)
        store.deleteGroup(other.id, keepingSnippets: false)
        XCTAssertNil(store.snippet(inside.id))
    }

    func testGroupOrder() {
        let first = store.groups[0].id
        store.moveGroup(first, by: 1)
        XCTAssertEqual(store.groups[1].id, first)
        store.moveGroup(first, by: -5)
        XCTAssertEqual(store.groups[0].id, first, "Moving past the start stops at the start")
        store.moveGroup(first, by: 99)
        XCTAssertEqual(store.groups.last?.id, first, "Moving past the end stops at the end")
        XCTAssertEqual(Set(store.groups.map(\.id)).count, store.groups.count, "No group is lost or duplicated")
    }

    func testUseCounting() {
        let snippet = store.add(trigger: "cnt", expansion: "counted")
        let before = store.totalUses
        store.recordUse(snippet.id)
        store.recordUse(snippet.id)
        XCTAssertEqual(store.snippet(snippet.id)?.useCount, 2)
        XCTAssertNotNil(store.snippet(snippet.id)?.lastUsed)
        XCTAssertEqual(store.totalUses, before + 2)
        XCTAssertEqual(store.uses(onDayOffset: 0), (store.dailyUses[SnippetStore.dayKey(for: Date())] ?? 0))
        store.undoUse(snippet.id)
        XCTAssertEqual(store.snippet(snippet.id)?.useCount, 1)
    }

    func testMergeSkipsExistingShortcuts() {
        let group = SnippetGroup(name: "Imported")
        var fresh = Snippet(trigger: "brand-new", expansion: "x")
        fresh.groupID = group.id
        let clash = Snippet(trigger: "eml", expansion: "should be skipped")
        let result = store.merge(QuillLibrary(snippets: [fresh, clash], groups: [group]))
        XCTAssertEqual(result.addedSnippets, 1)
        XCTAssertEqual(result.addedGroups, 1)
        XCTAssertTrue(store.containsTrigger("brand-new"))
        let imported = store.snippets.first { $0.trigger == "brand-new" }
        XCTAssertEqual(imported.flatMap(store.group(for:))?.name, "Imported")
    }

    func testSnippetColourFallsBackToGroup() {
        let group = store.addGroup(named: "Tinted")
        store.updateGroup(group.id) { $0.color = .green }
        var snippet = store.add(trigger: "tint", expansion: "x", groupID: group.id)
        XCTAssertEqual(store.tint(for: snippet), GroupColor.green.color, "No colour of its own: the group's")
        store.update(snippet.id) { $0.color = "purple" }
        snippet = store.snippet(snippet.id)!
        XCTAssertEqual(store.tint(for: snippet), GroupColor.purple.color, "Its own system colour wins")
        XCTAssertNotNil(QuillColor.resolve("#336699"))
        XCTAssertNil(QuillColor.resolve("not a colour"))
        XCTAssertNil(QuillColor.resolve(nil))
        XCTAssertEqual(store.group(group.id)?.colorValue, "green")
        store.updateGroup(group.id) { $0.customColor = "#336699" }
        XCTAssertEqual(store.group(group.id)?.colorValue, "#336699", "A custom colour wins over the preset")
    }

    func testMoveSnippetsBeforeAnother() {
        let a = store.add(trigger: "ma", expansion: "a")
        let b = store.add(trigger: "mb", expansion: "b")
        let group = store.addGroup(named: "Target")
        let c = store.add(trigger: "mc", expansion: "c", groupID: group.id)
        store.move([a.id, b.id], before: c.id, in: nil)
        let order = store.snippets.map(\.id)
        let ia = order.firstIndex(of: a.id)!, ib = order.firstIndex(of: b.id)!, ic = order.firstIndex(of: c.id)!
        XCTAssertTrue(ia < ib && ib < ic, "Moved snippets land just before the target, keeping their order")
        XCTAssertEqual(store.snippet(a.id)?.groupID, group.id, "They join the target's group")
        store.move([c.id], before: c.id, in: nil)
        XCTAssertEqual(store.snippets.map(\.id), order, "Dropping a snippet on itself changes nothing")
        store.move([a.id], before: nil, in: nil)
        XCTAssertNil(store.snippet(a.id)?.groupID, "Dropping on a header moves it to the end of that group")
    }

    func testMoveGroupBefore() {
        let ids = store.groups.map(\.id)
        store.moveGroup(ids[2], before: ids[0])
        XCTAssertEqual(store.groups.map(\.id), [ids[2], ids[0], ids[1]])
        store.moveGroup(ids[2], before: nil)
        XCTAssertEqual(store.groups.map(\.id), ids)
    }

    func testManualOrderKeepsLibraryOrder() {
        let order = store.snippets
        XCTAssertEqual(SnippetSortOrder.manual.sorted(order).map(\.id), order.map(\.id))
        XCTAssertEqual(SnippetDrag.snippetIDs(from: SnippetDrag.payload(for: order.prefix(2).map(\.id))), order.prefix(2).map(\.id))
        XCTAssertNotNil(SnippetDrag.groupID(from: SnippetDrag.groupPayload(for: UUID())))
        XCTAssertTrue(SnippetDrag.snippetIDs(from: "plain text").isEmpty)
    }

    func testStarterPacks() {
        let pack = StarterPack.all[0]
        XCTAssertNil(store.installedGroup(for: pack))
        let added = store.install(pack)
        XCTAssertGreaterThan(added, 0)
        XCTAssertNotNil(store.installedGroup(for: pack))
        store.uninstall(pack)
        XCTAssertNil(store.installedGroup(for: pack))
    }
}

/// The app-level filters the sidebar uses.
@MainActor
final class ScopeTests: XCTestCase {
    func testScopes() {
        let state = AppState.shared
        let all = state.snippets(in: .all)
        XCTAssertEqual(all.count, state.store.snippets.count)
        XCTAssertEqual(state.snippets(in: .enabled).count + state.snippets(in: .disabled).count, all.count)
        XCTAssertTrue(state.snippets(in: .tokens).allSatisfy { TokenRenderer.containsTokens($0.expansion) })
        XCTAssertTrue(state.snippets(in: .recent).allSatisfy { $0.lastUsed != nil })
        for group in state.store.groups {
            XCTAssertTrue(state.snippets(in: .group(group.id)).allSatisfy { $0.groupID == group.id })
            XCTAssertEqual(state.title(for: .group(group.id)), group.name)
        }
        XCTAssertEqual(state.title(for: .all), "All Quills")
    }

    func testSidebarSelectionDrivesThePage() {
        let state = AppState.shared
        state.selection = [.history]
        XCTAssertEqual(state.page, .history)
        state.selection = [.overview]
        XCTAssertEqual(state.page, .stats)
        if let snippet = state.store.snippets.first {
            state.selection = [.snippet(snippet.id)]
            XCTAssertEqual(state.page, .snippets)
            XCTAssertEqual(state.selectedSnippetIDs, [snippet.id])
        }
        state.page = .history
        XCTAssertEqual(state.selection, [.history], "Setting the page selects it in the sidebar")
        state.page = .stats
        XCTAssertEqual(state.selection, [.overview])
        state.page = .settings
        XCTAssertEqual(state.selection, [.settings], "Settings is a page in the main window")
        XCTAssertEqual(state.page, .settings)
        state.showSettings(.backup)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "settingsPane"), "backup", "Opening a pane remembers it")
        state.page = .snippets
        XCTAssertTrue(state.selection.isEmpty, "Leaving Settings clears the selection")
        state.page = .snippets
        XCTAssertTrue(state.selection.isEmpty)
    }
}

/// The keystroke-level engine checks that also run with -QuillSelfTest.
@MainActor
final class EngineTests: XCTestCase {
    func testEngineSelfTestPasses() {
        XCTAssertTrue(EngineSelfTest.run())
    }
}
