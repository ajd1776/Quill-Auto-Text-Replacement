import SwiftUI

/// A mock text field that types a shortcut, then plays the chosen replacement animations
/// together, using the same effect views Quill draws over other apps.
struct AnimationPreview: View {
    /// Every effect to play. The typewriter types the text; the rest play over it at once.
    let styles: [ReplacementAnimation]
    let speed: Double
    let trigger: String
    let expansion: String
    /// True when Reduce Motion is on and the person hasn't chosen to play animations anyway.
    let reduceMotion: Bool
    /// Room above the field for effects that rise off the text.
    var height: CGFloat = 150
    /// Text before the shortcut in the mock field.
    var prefix = "Email me at "
    /// A small version for the effect gallery: smaller text and field, no replay button.
    var compact = false
    /// Waits this long before the first play, so a gallery of previews starts one after another.
    var startDelay: Double = 0
    /// Changing it replays the preview (the gallery replays a tile on hover).
    var replayToken = 0

    @State private var shown = ""
    @State private var effects: [ReplacementAnimation] = []
    @State private var effectID = 0
    @State private var task: Task<Void, Never>?
    @State private var textFrame: CGRect = .zero

    private static let space = "animationPreview"

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Text(prefix)
                        .foregroundStyle(.secondary)
                    Text(shown)
                        .lineLimit(1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { textFrame = $0 }
                    Rectangle()
                        .fill(.tint)
                        .frame(width: 2, height: compact ? 14 : 18)
                    Spacer(minLength: 0)
                }
                .font(.system(size: fontSize))
                .padding(.horizontal, compact ? 9 : 14)
                .frame(height: compact ? 28 : 40)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: compact ? 9 : 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 9 : 8, style: .continuous).strokeBorder(.separator)
                }
                Spacer(minLength: 0).frame(height: compact ? 8 : 34)
            }

            ForEach(effects, id: \.self) { effect in
                OverlayEffectView(style: effect, context: EffectContext(
                    line: textFrame,
                    caret: CGPoint(x: textFrame.maxX + 1, y: textFrame.midY),
                    text: expansion,
                    trigger: trigger,
                    fontSize: fontSize,
                    reduceMotion: reduceMotion
                ))
                .id("\(effect.rawValue)-\(effectID)")
                .allowsHitTesting(false)
            }
        }
        .coordinateSpace(.named(Self.space))
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            if !compact {
                Button("Replay Preview", systemImage: "arrow.counterclockwise", action: play)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Replay Preview")
            }
        }
        .onAppear { play(after: startDelay) }
        .onChange(of: replayToken) { play() }
        .onChange(of: styles) { play() }
        .onChange(of: reduceMotion) { play() }
        .onDisappear { task?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(styles.map(\.title).joined(separator: " and "))")
    }

    private var fontSize: CGFloat { compact ? 12 : 15 }

    private func play() { play(after: 0) }

    private func play(after delay: Double) {
        task?.cancel()
        task = Task { @MainActor in
            shown = ""
            effects = []
            try? await Task.sleep(for: .milliseconds(350 + Int(delay * 1000)))
            for character in trigger {
                guard !Task.isCancelled else { return }
                shown.append(character)
                try? await Task.sleep(for: .milliseconds(120))
            }
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }

            let playable = styles.filter { $0 != .instant && (!reduceMotion || $0.survivesReduceMotion) }
            if playable.contains(.typewriter) {
                shown = ""
                let interval = min(1 / max(speed, 1), 3.0 / Double(max(expansion.count, 1)))
                for character in expansion {
                    guard !Task.isCancelled else { return }
                    shown.append(character)
                    try? await Task.sleep(for: .seconds(interval))
                }
            } else {
                shown = expansion
            }
            // Every other effect plays over the finished text, all at once, as in other apps.
            let overlays = playable.filter { $0 != .typewriter }
            guard !overlays.isEmpty, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(40))
            effectID += 1
            effects = overlays
            let longest = overlays.map(OverlayEffectView.duration(for:)).max() ?? 1
            try? await Task.sleep(for: .seconds(longest))
            if !Task.isCancelled { effects = [] }
        }
    }
}
