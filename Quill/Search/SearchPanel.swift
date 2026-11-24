import AppKit
import Observation
import SwiftUI

/// Search state for the snippet search panel.
@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet { selection = 0 }
    }
    var selection = 0

    private let store: SnippetStore

    init(store: SnippetStore) {
        self.store = store
    }

    var hasSnippets: Bool {
        store.snippets.contains { !$0.expansion.isEmpty }
    }

    /// Matching snippets, most used first.
    var results: [Snippet] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let candidates = store.snippets.filter { !$0.expansion.isEmpty }
        let matching = query.isEmpty ? candidates : candidates.filter {
            $0.matches(query)
        }
        return Array(matching.sorted(by: SnippetSortOrder.mostUsed.areInIncreasingOrder).prefix(50))
    }

    var selectedSnippet: Snippet? {
        let results = results
        return results.indices.contains(selection) ? results[selection] : nil
    }

    func move(by delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }
}

/// A Spotlight-style floating panel for finding a snippet and inserting it where you're typing.
///
/// It's a non-activating panel, so the app you're typing in stays frontmost and gets the text.
@MainActor
final class SearchPanelController: NSObject, NSWindowDelegate {
    static let shared = SearchPanelController()

    private var panel: FloatingPanel?
    private var model: SearchModel?
    private var keyMonitor: Any?
    private let width: CGFloat = 640

    var isVisible: Bool { panel != nil }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard panel == nil else { return }
        let state = AppState.shared
        let model = SearchModel(store: state.store)

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let top = visible.maxY - visible.height * 0.2
        let height: CGFloat = 64
        let panel = FloatingPanel(contentRect: CGRect(x: visible.midX - width / 2, y: top - height, width: width, height: height))

        let root = SearchPanelView(
            model: model,
            width: width,
            onCommit: { [weak self] snippet in self?.insert(snippet) },
            onHeightChange: { [weak self] height in self?.resize(to: height) }
        )
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self

        self.panel = panel
        self.model = model
        state.setSearchPanelOpen(true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        model = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
        AppState.shared.setSearchPanelOpen(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func insert(_ snippet: Snippet) {
        close()
        // Give focus a moment to return to the app you were typing in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            AppState.shared.insert(snippet, after: 0)
        }
    }

    /// Grows and shrinks downward from a fixed top edge as results change.
    private func resize(to height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let isPanelKey = event.window is FloatingPanel
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard isPanelKey, let self, let model = self.model else { return false }
                switch keyCode {
                case 125: // ↓
                    model.move(by: 1)
                case 126: // ↑
                    model.move(by: -1)
                case 36, 76: // Return
                    if let snippet = model.selectedSnippet { self.insert(snippet) }
                case 53: // Esc
                    self.close()
                default:
                    return false
                }
                return true
            }
            return handled ? nil : event
        }
    }
}

final class FloatingPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct SearchPanelView: View {
    @Bindable var model: SearchModel
    let width: CGFloat
    let onCommit: (Snippet) -> Void
    let onHeightChange: (CGFloat) -> Void

    @FocusState private var isFieldFocused: Bool
    private let rowHeight: CGFloat = 48

    var body: some View {
        let results = model.results

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search Quills", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($isFieldFocused)
                    .accessibilityLabel("Search quills")
            }
            .padding(.horizontal, 20)
            .frame(height: 64)

            if !results.isEmpty {
                Divider().padding(.horizontal, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, snippet in
                                SearchResultRow(snippet: snippet, isSelected: index == model.selection)
                                    .frame(height: rowHeight)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onCommit(snippet) }
                                    .onHover { if $0 { model.selection = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: min(CGFloat(results.count), 7) * (rowHeight + 2) + 16)
                    .onChange(of: model.selection) { _, selection in
                        proxy.scrollTo(selection)
                    }
                }
                Divider().padding(.horizontal, 12)
                HStack(spacing: 16) {
                    hint("↑↓", "Choose")
                    hint("↩", "Insert")
                    hint("esc", "Close")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 32)
            } else {
                Divider().padding(.horizontal, 12)
                Text(model.hasSnippets ? "No Matching Quills" : "No quills yet. Add some in the Quill library.")
                    .foregroundStyle(.secondary)
                    .frame(height: 52)
            }
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
}

private struct SearchResultRow: View {
    let snippet: Snippet
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(snippet.trigger.isEmpty ? "—" : snippet.trigger)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isSelected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            Text(snippet.preview)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer(minLength: 8)
            if snippet.useCount > 0 {
                Text("\(snippet.useCount)×")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
