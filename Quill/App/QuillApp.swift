import SwiftUI

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared
    @AppStorage(AppState.showMenuBarExtraKey) private var showsMenuBarExtra = true
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    var body: some Scene {
        Window("Quill", id: WindowID.library) {
            LibraryView()
                .environment(state)
        }
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(hasCompletedWelcome && showsMenuBarExtra ? .suppressed : .presented)
        .commands {
            QuillCommands(state: state)
        }

        Window("Welcome to Quill", id: WindowID.welcome) {
            WelcomeView()
                .environment(state)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(hasCompletedWelcome ? .suppressed : .presented)

        MenuBarExtra(isInserted: $showsMenuBarExtra) {
            MenuBarPanel()
                .environment(state)
        } label: {
            MenuBarLabel()
                .environment(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

enum WindowID {
    static let library = "library"
    static let welcome = "welcome"
}

/// The menu bar icon. Also the one view that exists from launch, so it hands AppKit
/// a way to open the library when Quill is opened again from Finder.
private struct MenuBarLabel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: state.menuBarIcon.image(isOn: state.status == .on))
            .accessibilityLabel(state.status == .on ? "Quill, on" : "Quill, off")
            .onAppear {
                state.openLibraryAction = { openWindow(id: WindowID.library) }
                #if DEBUG
                runDemoIfRequested()
                #endif
            }
    }

    #if DEBUG
    static var demoPanel: NSWindow?

    /// Opens a window or overlay at launch for screenshots: -QuillDemo library|settings|search|badge|sparkle|hud
    private func runDemoIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-QuillDemo"), index + 1 < arguments.count else { return }
        let demo = arguments[index + 1]
        if arguments.contains("-QuillLight") { NSApp.appearance = NSAppearance(named: .aqua) }
        // Screenshots use the default window size, whatever size the window was last left at.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard !demo.hasPrefix("stage:") else { return }
            for window in NSApp.windows where window.identifier?.rawValue.contains(WindowID.library) == true {
                window.setFrame(NSRect(x: 160, y: 120, width: 1320, height: 820), display: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch demo {
            case "library":
                UserDefaults.standard.set("list", forKey: "snippetLayout")
                openWindow(id: WindowID.library)
            case "grid":
                UserDefaults.standard.set("grid", forKey: "snippetLayout")
                openWindow(id: WindowID.library)
            case "overview", "stats":
                state.page = .stats
                openWindow(id: WindowID.library)
            case "panel":
                let host = NSHostingController(rootView: MenuBarPanel().environment(state).ignoresSafeArea())
                let window = NSPanel(contentViewController: host)
                window.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.title = "Quill Panel"
                window.hidesOnDeactivate = false
                window.center()
                window.orderFrontRegardless()
                Self.demoPanel = window
            case "editor":
                openWindow(id: WindowID.library)
                let snippets = state.store.snippets.sorted(by: state.sortOrder.areInIncreasingOrder)
                if let pick = snippets.first(where: { $0.trigger == "thx" || $0.trigger == "eAD" }) ?? snippets.first {
                    state.selection = [.snippet(pick.id)]
                }
            case "welcome":
                openWindow(id: WindowID.welcome)
            case "general", "suggestions", "effects", "shortcuts", "backup", "about":
                UserDefaults.standard.set(demo, forKey: "settingsPane")
                state.page = .settings
                openWindow(id: WindowID.library)
            case "history":
                state.page = .history
                openWindow(id: WindowID.library)
            case "packs":
                openWindow(id: WindowID.library)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { state.isShowingPacks = true }
            case "iconpicker":
                openWindow(id: WindowID.library)
                if let group = state.store.groups.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { state.iconPickerTarget = .group(group.id) }
                }
            case "update":
                openWindow(id: WindowID.library)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { state.updates.isShowingDetails = true }
            case "palette":
                openWindow(id: WindowID.library)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { state.isShowingPalette = true }
            case "fillin":
                var sample = Snippet(trigger: "thx", expansion: "Hi {input:Name}, thanks for your order {input:Order}! It ships {date}.")
                sample.symbol = "shippingbox.fill"
                FillInController.demoWithoutFocus = true
                FillInController.shared.present(snippet: sample, fields: ["Name", "Order"]) { _ in }
            case "search":
                SearchPanelController.shared.show()
            case "bubble":
                let snippets = state.store.activeSnippets.sorted(by: SnippetSortOrder.shortcut.areInIncreasingOrder)
                let items = snippets.filter { $0.trigger.hasPrefix("si") }.prefix(3).map {
                    ExpansionEngine.Suggestion(snippet: $0, typedCount: 2)
                }
                SuggestionBubbleController.shared.showDemo(Array(items))
            case "hud":
                OverlayPresenter.shared.showToggleHUD(isOn: true)
            case let scene where scene.hasPrefix("stage:"):
                DemoStage.shared.run(String(scene.dropFirst(6))) { openWindow(id: WindowID.library) }
            default:
                // -QuillDemo <style>, such as cyber or confetti, plays that effect under the pointer.
                if let style = ReplacementAnimation(rawValue: demo) {
                    let pointer = NSEvent.mouseLocation
                    let line = CGRect(x: pointer.x - 160, y: pointer.y - 20, width: 160, height: 20)
                    OverlayPresenter.shared.play(style, trigger: "eml", text: "name@example.com",
                                                 at: CaretLocator.Geometry(caret: CGRect(x: line.maxX, y: line.minY, width: 1, height: 20), line: line))
                }
            }
        }
    }
    #endif
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quill works with no windows open, so macOS must never quit it quietly to save memory.
    /// SwiftUI apps opt into automatic termination by default; switch it off before launch finishes.
    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = false
        ProcessInfo.processInfo.disableAutomaticTermination("Quill expands snippets in the background")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = false
        MainActor.assumeIsolated {
            #if DEBUG
            if CommandLine.arguments.contains("-QuillSelfTest") {
                exit(EngineSelfTest.run() ? 0 : 1)
            }
            // Runs one real update check against GitHub, prints the outcome and quits.
            if CommandLine.arguments.contains("-QuillUpdateCheck") {
                Task { @MainActor in
                    let updates = AppState.shared.updates
                    await updates.check(manual: true)
                    print("current \(UpdateChecker.currentVersion) → \(updates.status)")
                    exit(0)
                }
            }
            #endif
            AppState.shared.updateActivationPolicy()
        }
    }

    /// Clicking the Dock icon or opening Quill again brings back the library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated {
                NSApp.activate()
                AppState.shared.openLibraryAction?()
            }
        }
        return true
    }

    /// Saves are batched a moment after each edit, so flush any pending one before quitting.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.store.save()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
