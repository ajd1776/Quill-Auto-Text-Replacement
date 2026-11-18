import AppKit
import SwiftUI

/// Shows short-lived, click-through overlays above every app: the replacement
/// effects at the cursor, and the on/off confirmation.
@MainActor
final class OverlayPresenter {
    static let shared = OverlayPresenter()

    private var panels: [NSPanel] = []
    /// The target app needs a moment to draw the inserted text before the cursor moves.
    private let settleDelay = 0.09
    /// Room around the text for effects that spill outside it.
    private let margin = CGSize(width: 170, height: 130)

    /// Plays an effect over the text just inserted. `override` places it somewhere specific instead (for demos).
    func play(_ style: ReplacementAnimation, trigger: String, text: String, at override: CaretLocator.Geometry? = nil) {
        guard style != .instant, style != .typewriter else { return }
        let reduceMotion = AppState.shared.shouldReduceMotion
        if reduceMotion, !style.survivesReduceMotion, override == nil { return }

        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? text
        if let override {
            show(style, trigger: trigger, text: text, geometry: override, reduceMotion: reduceMotion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            let length = lastLine.count
            CaretLocator.lookup({ CaretLocator.geometry($0, lineLength: length) }) { found in
                var geometry = found.map {
                    CaretLocator.Geometry(caret: $0.caret, line: $0.line ?? CaretLocator.estimatedLine(endingAt: $0.caret, text: lastLine))
                }
                if geometry == nil, style == .popBadge {
                    let pointer = CaretLocator.pointerRect()
                    geometry = CaretLocator.Geometry(caret: pointer, line: pointer)
                }
                guard let geometry else { return }
                self.show(style, trigger: trigger, text: text, geometry: geometry, reduceMotion: reduceMotion)
            }
        }
    }

    private func show(_ style: ReplacementAnimation, trigger: String, text: String,
                      geometry: CaretLocator.Geometry, reduceMotion: Bool) {
        let area = geometry.line.union(geometry.caret).insetBy(dx: -self.margin.width, dy: -self.margin.height)
        let frame = self.clamped(area)
        func local(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let caret = local(geometry.caret)
        let context = EffectContext(
            line: local(geometry.line),
            caret: CGPoint(x: caret.midX, y: caret.midY),
            text: text,
            trigger: trigger,
            fontSize: max(11, geometry.caret.height * 0.78),
            reduceMotion: reduceMotion
        )
        self.present(OverlayEffectView(style: style, context: context), frame: frame,
                     duration: OverlayEffectView.duration(for: style))
    }

    func showToggleHUD(isOn: Bool) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = CGSize(width: 240, height: 110)
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.12)
        present(ToggleHUDView(isOn: isOn), frame: CGRect(origin: origin, size: size), duration: 1.4)
    }

    private func present<Content: View>(_ content: Content, frame: CGRect, duration: TimeInterval) {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: content.frame(width: frame.width, height: frame.height))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        panels.append(panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            panel.orderOut(nil)
            self?.panels.removeAll { $0 === panel }
        }
    }

    /// Keeps an overlay on the screen it starts on.
    private func clamped(_ frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return frame }
        return frame.intersection(screen.frame)
    }
}
