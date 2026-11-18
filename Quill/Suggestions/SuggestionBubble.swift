import AppKit
import Observation
import SwiftUI

enum BubblePosition: String, CaseIterable, Identifiable {
    case below, above
    var id: String { rawValue }
    var title: String { self == .below ? "Below the Text" : "Above the Text" }
}

@MainActor
@Observable
final class SuggestionModel {
    var items: [ExpansionEngine.Suggestion] = []
    var highlighted = 0
}

/// The live suggestion bubble: appears at the cursor while you type a shortcut,
/// like the macOS text replacement bubble. Click-through and never takes focus.
@MainActor
final class SuggestionBubbleController {
    static let shared = SuggestionBubbleController()

    private let model = SuggestionModel()
    private var panel: NSPanel?
    private var pending: DispatchWorkItem?
    private var idleHide: DispatchWorkItem?
    /// Bumped on every change, so a slow cursor lookup for old suggestions is ignored.
    private var generation = 0
    /// A bubble left up this long with no typing is stale (for example, focus moved to a password field).
    private let idleTimeout: TimeInterval = 8

    private var isShowing: Bool { panel?.isVisible == true }

    func update(_ items: [ExpansionEngine.Suggestion], highlighted: Int) {
        let onlyHighlightChanged = items == model.items && isShowing
        model.items = items
        model.highlighted = highlighted
        generation += 1
        pending?.cancel()
        guard !items.isEmpty else {
            hide()
            return
        }
        scheduleIdleHide()
        guard !onlyHighlightChanged else { return }
        // Wait for the app to draw the character just typed, so the cursor has moved.
        let token = generation
        let work = DispatchWorkItem { [weak self] in self?.locateAndShow(token: token) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
    }

    func hide() {
        pending?.cancel()
        idleHide?.cancel()
        panel?.orderOut(nil)
        // The engine only treats Tab, Esc and ↑↓ as bubble keys while the bubble is actually visible.
        ExpansionEngine.shared.isBubbleVisible = false
    }

    #if DEBUG
    func showDemo(_ items: [ExpansionEngine.Suggestion]) {
        model.items = items
        model.highlighted = 0
        show(at: CaretLocator.pointerRect())
    }
    #endif

    private func scheduleIdleHide() {
        idleHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        idleHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    private func locateAndShow(token: Int) {
        CaretLocator.lookup({ CaretLocator.caret($0, fieldFallback: false) }) { [weak self] caret in
            guard let self, token == self.generation, !self.model.items.isEmpty else { return }
            guard let caret else {
                quillLog.debug("Bubble: no cursor position, so hidden")
                self.hide()
                return
            }
            self.show(at: caret)
        }
    }

    private func show(at caret: CGRect) {
        guard !model.items.isEmpty else { return hide() }
        let size = SuggestionBubbleView.size(for: model.items.count)
        let gap: CGFloat = 5
        let below = caret.minY - size.height - gap
        let above = caret.maxY + gap
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) }?.visibleFrame ?? .infinite

        var y: CGFloat
        // Above the text, like the system's suggestion bubble; below only when there's no room at the top.
        y = above + size.height > screen.maxY ? below : above
        y = min(max(y, screen.minY), screen.maxY - size.height)
        let x = min(max(caret.minX - 14, screen.minX), screen.maxX - size.width)

        let panel = panel ?? makePanel()
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        ExpansionEngine.shared.isBubbleVisible = true
        quillLog.debug("Bubble: shown with \(self.model.items.count, privacy: .public) suggestions at \(Int(x), privacy: .public),\(Int(y), privacy: .public)")
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: SuggestionBubbleView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }
}

struct SuggestionBubbleView: View {
    let model: SuggestionModel

    static let width: CGFloat = 360
    static let rowHeight: CGFloat = 30
    static let footerHeight: CGFloat = 24
    private static let padding: CGFloat = 5

    static func size(for count: Int) -> CGSize {
        CGSize(width: width, height: CGFloat(count) * rowHeight + padding * 2 + footerHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                SuggestionRow(item: item, isHighlighted: index == model.highlighted)
                    .frame(height: Self.rowHeight)
            }
            HStack(spacing: 12) {
                hint(model.items.first?.isExact == true ? "space" : "⇥", "Accept")
                if model.items.count > 1 { hint("↑↓", "Choose") }
                hint("esc", "Dismiss")
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: Self.footerHeight)
        }
        .padding(Self.padding)
        .frame(width: Self.width, height: Self.size(for: model.items.count).height, alignment: .top)
        .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(action)
                .font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
    }
}

private struct SuggestionRow: View {
    let item: ExpansionEngine.Suggestion
    let isHighlighted: Bool

    var body: some View {
        let trigger = item.snippet.trigger
        let typed = String(trigger.prefix(item.typedCount))
        let rest = String(trigger.dropFirst(item.typedCount))
        let preview = TokenRenderer.render(item.snippet.expansion, clipboard: "Clipboard").text
            .replacingOccurrences(of: "\n", with: " ")

        HStack(spacing: 10) {
            (Text(typed).fontWeight(.bold) + Text(rest).foregroundStyle(isHighlighted ? .white.opacity(0.75) : .secondary))
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 44, alignment: .leading)
            Text(preview)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(isHighlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
