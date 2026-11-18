import SwiftUI

/// Menu bar commands, so everything in the library window is also reachable from the menus.
struct QuillCommands: Commands {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                showLibrary()
                Task { await state.updates.check(manual: true) }
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                showLibrary()
                state.page = .settings
            }
            .keyboardShortcut(",")
        }

        CommandGroup(after: .appSettings) {
            Toggle("Expand Snippets", isOn: Binding(
                get: { state.isOn },
                set: { state.setOn($0) }
            ))
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("New Snippet") {
                showLibrary()
                state.newSnippet()
            }
            .keyboardShortcut("n")

            Button("New Group") {
                showLibrary()
                state.newGroup()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Duplicate") {
                state.duplicateSelection()
            }
            .keyboardShortcut("d")
            .disabled(state.selectedSnippetIDs.isEmpty)

            Divider()

            Button("Import Text Replacements from macOS…") {
                showLibrary()
                state.beginSystemImport()
            }

            Button("Import Snippets…") {
                showLibrary()
                state.isShowingFileImporter = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Add Starter Pack…") {
                showLibrary()
                state.isShowingPacks = true
            }

            Button("Export Snippets…") {
                state.exportLibrary()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Snippet") {
            SnippetActionsMenu(ids: state.selectedSnippetIDs) { ids in
                state.store.delete(ids, undoManager: nil)
                state.selection = []
            }
            .environment(state)
            .disabled(state.selectedSnippetIDs.isEmpty)
        }

        CommandGroup(before: .toolbar) {
            Button("Command Palette") {
                showLibrary()
                state.isShowingPalette = true
            }
            .keyboardShortcut("k")

            ForEach(Array(AppPage.allCases.enumerated()), id: \.element) { index, page in
                Button("Show \(page.title)") {
                    showLibrary()
                    state.page = page
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }

            Picker("Sort By", selection: Binding(
                get: { state.sortOrder },
                set: { state.sortOrder = $0 }
            )) {
                ForEach(SnippetSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            Divider()
        }
    }

    private func showLibrary() {
        openWindow(id: WindowID.library)
    }
}
