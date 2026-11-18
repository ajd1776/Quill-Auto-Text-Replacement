import SwiftUI

/// Where an effect plays, in the overlay's own coordinates (origin top-left).
struct EffectContext {
    /// The last line of inserted text.
    var line: CGRect
    /// The cursor, at the end of the inserted text.
    var caret: CGPoint
    var text: String
    var trigger: String
    var fontSize: CGFloat
    var reduceMotion: Bool
}

/// Plays one replacement effect. Each effect runs once from when it appears.
struct OverlayEffectView: View {
    let style: ReplacementAnimation
    let context: EffectContext

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            switch style {
            case .instant, .typewriter:
                EmptyView()
            case .popBadge:
                BadgeView(trigger: context.trigger, expansion: context.text, reduceMotion: context.reduceMotion)
                    .fixedSize()
                    .position(x: context.caret.x, y: context.line.minY - 18)
            case .glow:
                GlowEffect(line: context.line, reduceMotion: context.reduceMotion)
            case .inkUnderline:
                InkUnderlineEffect(line: context.line)
            case .fadeIn, .slideIn, .bounceIn:
                GhostTextEffect(style: style, context: context)
            case .sparkle:
                SparkleBurstView(size: 160)
                    .position(context.caret)
            case .confetti:
                ConfettiEffect(origin: context.caret)
            case .ripple:
                RippleEffect(center: context.caret)
            case .particleCloud:
                ParticleCloudEffect(line: context.line)
            case .cyber:
                CyberDecodeEffect(text: context.text)
                    .fixedSize()
                    .position(x: max(context.line.midX, context.caret.x - 120), y: context.line.minY - 20)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// How long the overlay stays up for each style.
    static func duration(for style: ReplacementAnimation) -> TimeInterval {
        switch style {
        case .instant, .typewriter: 0
        case .popBadge, .cyber: 1.8
        case .glow: 1.2
        case .inkUnderline, .fadeIn, .slideIn, .bounceIn, .confetti: 1.5
        case .sparkle: 0.9
        case .ripple: 1.1
        case .particleCloud: 1.6
        }
    }
}

// MARK: - Clock

/// Seconds since the view appeared, driven by the display's frame rate.
private struct EffectClock<Content: View>: View {
    @ViewBuilder let content: (Double) -> Content
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            content(timeline.date.timeIntervalSince(start))
        }
    }
}

private func progress(_ time: Double, from start: Double, over length: Double) -> Double {
    min(max((time - start) / length, 0), 1)
}

private func easeOut(_ value: Double) -> Double {
    1 - pow(1 - value, 3)
}

/// Deterministic pseudo-random number in 0...1, so effects don't jitter when SwiftUI redraws.
private func noise(_ seed: Int) -> Double {
    let value = sin(Double(seed) * 12.9898 + 78.233) * 43_758.5453
    return value - value.rounded(.down)
}

// MARK: - Glow

private struct GlowEffect: View {
    let line: CGRect
    let reduceMotion: Bool

    var body: some View {
        EffectClock { time in
            let fadeIn = progress(time, from: 0, over: 0.15)
            let fadeOut = progress(time, from: 0.65, over: 0.5)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.28))
                .frame(width: line.width + 10, height: line.height + 6)
                .opacity(fadeIn * (1 - fadeOut))
                .position(x: line.midX, y: line.midY)
        }
    }
}

// MARK: - Ink underline

private struct InkStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let segments = max(2, Int(rect.width / 60))
        let step = rect.width / CGFloat(segments)
        path.move(to: CGPoint(x: 0, y: rect.midY + 1))
        for index in 1...segments {
            let x = step * CGFloat(index)
            let lift: CGFloat = index.isMultiple(of: 2) ? -1.5 : 1.5
            path.addQuadCurve(
                to: CGPoint(x: x, y: rect.midY + lift * 0.4),
                control: CGPoint(x: x - step / 2, y: rect.midY + lift * 1.6)
            )
        }
        return path
    }
}

private struct InkUnderlineEffect: View {
    let line: CGRect

    var body: some View {
        EffectClock { time in
            let drawn = easeOut(progress(time, from: 0.05, over: 0.45))
            let fadeOut = progress(time, from: 0.95, over: 0.5)
            ZStack {
                InkStroke()
                    .trim(from: 0, to: drawn)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                InkStroke()
                    .trim(from: 0, to: drawn * 0.97)
                    .stroke(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .offset(y: 2.5)
            }
            .frame(width: line.width + 4, height: 10)
            .opacity(1 - fadeOut)
            .position(x: line.midX, y: line.maxY + 3)
        }
    }
}

// MARK: - Ghost text (Fade In, Slide In, Bounce In)

private struct GhostTextEffect: View {
    let style: ReplacementAnimation
    let context: EffectContext

    @State private var arrived = false
    @State private var melted = false

    private var lineText: String {
        let last = context.text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? context.text
        return last.count > 80 ? String(last.suffix(80)) : last
    }

    var body: some View {
        Text(lineText)
            .font(.system(size: context.fontSize))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassSurface(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .fixedSize()
            .scaleEffect(melted ? 1.04 : 1)
            .blur(radius: melted ? 6 : 0)
            .opacity(melted ? 0 : (arrived ? 1 : 0))
            .offset(x: arrived ? 0 : startOffset.width, y: arrived ? 0 : startOffset.height)
            .offset(x: context.line.minX - 6, y: context.line.minY - 2)
            .onAppear {
                let arrival: Animation = switch style {
                case .bounceIn where !context.reduceMotion: .spring(response: 0.42, dampingFraction: 0.42)
                case .slideIn where !context.reduceMotion: .spring(response: 0.38, dampingFraction: 0.85)
                default: .easeOut(duration: 0.3)
                }
                withAnimation(arrival) { arrived = true }
                withAnimation(.easeIn(duration: 0.45).delay(0.95)) { melted = true }
            }
    }

    private var startOffset: CGSize {
        guard !context.reduceMotion else { return .zero }
        switch style {
        case .slideIn: return CGSize(width: 60, height: 0)
        case .bounceIn: return CGSize(width: 0, height: -46)
        default: return .zero
        }
    }
}

// MARK: - Confetti

private struct ConfettiEffect: View {
    let origin: CGPoint
    private let colors: [Color] = [.accentColor, .pink, .orange, .yellow, .mint, .purple]
    private let count = 28

    var body: some View {
        EffectClock { time in
            let fadeOut = progress(time, from: 0.85, over: 0.55)
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let angle = (-150 + 120 * noise(index)) * .pi / 180
                    let speed = 150 + 140 * noise(index + 50)
                    let x = cos(angle) * speed * time
                    let y = sin(angle) * speed * time + 0.5 * 560 * time * time
                    let isStrip = index % 3 != 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colors[index % colors.count])
                        .frame(width: isStrip ? 7 : 5, height: isStrip ? 3 : 5)
                        .rotationEffect(.degrees(time * (300 + 400 * noise(index + 9)) * (index.isMultiple(of: 2) ? 1 : -1)))
                        .position(x: origin.x + x, y: origin.y + y)
                }
            }
            .opacity(1 - fadeOut)
        }
    }
}

// MARK: - Ripple

private struct RippleEffect: View {
    let center: CGPoint

    var body: some View {
        EffectClock { time in
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let value = easeOut(progress(time, from: Double(ring) * 0.15, over: 0.8))
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2.5 * (1 - value) + 0.5)
                        .frame(width: 8 + value * 120, height: 8 + value * 120)
                        .opacity(value > 0 ? 1 - value : 0)
                }
            }
            .position(center)
        }
    }
}

// MARK: - Particle cloud

private struct ParticleCloudEffect: View {
    let line: CGRect
    private let colors: [Color] = [.accentColor, .cyan, .indigo, .teal]
    private let count = 36

    var body: some View {
        EffectClock { time in
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let start = line.minX + line.width * noise(index)
                    let rise = (28 + 46 * noise(index + 100)) * easeOut(progress(time, from: 0, over: 1.3))
                    let sway = sin(time * 4 + Double(index)) * 6
                    let size = 3 + 5 * noise(index + 200)
                    let life = progress(time, from: 0.05 * noise(index + 300), over: 1.35)
                    Circle()
                        .fill(colors[index % colors.count])
                        .frame(width: size, height: size)
                        .blur(radius: 1.2)
                        .opacity(life < 0.2 ? life / 0.2 : max(0, 1 - (life - 0.2) / 0.8))
                        .position(x: start + sway, y: line.midY - rise)
                }
            }
        }
    }
}

// MARK: - Cyber decode

private struct CyberDecodeEffect: View {
    let text: String
    private let glyphs = Array("!<>-_\\/[]{}=+*^?#01ABCDEFXZ$%&")

    private var line: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? text
        return first.count > 40 ? String(first.prefix(39)) + "…" : first
    }

    var body: some View {
        EffectClock { time in
            let characters = Array(line)
            let step = min(0.045, 0.7 / Double(max(characters.count, 1)))
            let frame = Int(time * 30)
            let shown = String(characters.enumerated().map { index, character in
                if character == " " || time > 0.08 + Double(index) * step { return character }
                return glyphs[Int(noise(index * 31 + frame) * Double(glyphs.count)) % glyphs.count]
            })
            let fadeOut = progress(time, from: 1.35, over: 0.4)

            Text(shown)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.82), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.cyan, lineWidth: 1.5)
                }
                .opacity((time < 0.12 ? time / 0.12 : 1) * (1 - fadeOut))
        }
    }
}
