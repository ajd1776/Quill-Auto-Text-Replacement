import SwiftUI

/// "eml → name@exa…" in a small glass capsule that pops up above the cursor, then floats away.
struct BadgeView: View {
    let trigger: String
    let expansion: String
    var reduceMotion = false
    var lifetime: Double = 1.5

    @State private var appeared = false
    @State private var leaving = false

    var body: some View {
        HStack(spacing: 7) {
            // Primary, not secondary: grey on grey glass falls below 4.5:1.
            Text(trigger)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tint)
            Text(preview)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassSurface(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .scaleEffect(reduceMotion || appeared ? 1 : 0.6, anchor: .bottom)
        .offset(y: reduceMotion ? 0 : (leaving ? -16 : (appeared ? 0 : 6)))
        .opacity(leaving ? 0 : (appeared ? 1 : 0))
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.6)) {
                appeared = true
            }
            withAnimation(.easeIn(duration: 0.4).delay(lifetime - 0.45)) {
                leaving = true
            }
        }
        .accessibilityHidden(true)
    }

    private var preview: String {
        let firstLine = expansion.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return firstLine.count > 36 ? String(firstLine.prefix(35)) + "…" : firstLine
    }
}

/// A short burst of sparkles from the cursor.
struct SparkleBurstView: View {
    var size: CGFloat = 160

    @State private var burst = false

    private struct Particle: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let pointSize: CGFloat
        let symbol: String
        let color: Color
        let spin: Double
    }

    /// Deterministic per index, so the burst doesn't change if SwiftUI rebuilds the view mid-animation.
    private var particles: [Particle] {
        let symbols = ["sparkle", "star.fill", "circle.fill", "sparkle"]
        let colors: [Color] = [.accentColor, .pink, .orange, .yellow, .mint]
        let count = 16
        return (0..<count).map { index in
            let jitter = sin(Double(index) * 12.9898) * 0.5 + 0.5
            return Particle(
                id: index,
                angle: Double(index) / Double(count) * 2 * .pi + jitter * 0.4,
                distance: size * (0.26 + 0.2 * jitter),
                pointSize: index % 4 == 2 ? 5 : 9 + 6 * jitter,
                symbol: symbols[index % symbols.count],
                color: colors[index % colors.count],
                spin: (jitter - 0.5) * 240
            )
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                .frame(width: burst ? size * 0.55 : 4, height: burst ? size * 0.55 : 4)
                .opacity(burst ? 0 : 0.9)

            ForEach(particles) { particle in
                Image(systemName: particle.symbol)
                    .font(.system(size: particle.pointSize, weight: .bold))
                    .foregroundStyle(particle.color)
                    .rotationEffect(.degrees(burst ? particle.spin : 0))
                    .scaleEffect(burst ? 0.25 : 1)
                    .offset(
                        x: burst ? cos(particle.angle) * particle.distance : 0,
                        y: burst ? sin(particle.angle) * particle.distance : 0
                    )
                    .opacity(burst ? 0 : 1)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { burst = true }
        }
        .accessibilityHidden(true)
    }
}

/// The on-screen confirmation shown when the global hotkey turns Quill on or off.
struct ToggleHUDView: View {
    let isOn: Bool
    var lifetime: Double = 1.3

    @State private var appeared = false
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "pencil.line" : "pencil.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Quill")
                    .font(.headline)
                Text(isOn ? "On" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .scaleEffect(reduceMotion || appeared ? 1 : 0.9)
        .opacity(leaving ? 0 : (appeared ? 1 : 0))
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { appeared = true }
            withAnimation(.easeIn(duration: 0.3).delay(lifetime - 0.35)) { leaving = true }
        }
    }
}
