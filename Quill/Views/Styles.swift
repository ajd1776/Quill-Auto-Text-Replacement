import AppKit
import SwiftUI

extension View {
    /// The prominent style for a window's one primary action: Liquid Glass on macOS 26, bordered before.
    @ViewBuilder
    func primaryActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// A floating surface for overlays and panels: Liquid Glass on macOS 26,
    /// a behind-window blur material before. Only used on the floating layer, never on content.
    func glassSurface<S: Shape>(_ shape: S) -> some View {
        modifier(GlassSurface(shape: shape))
    }

    /// Tells AppState when a window opens and closes, so Quill can show or hide its Dock icon.
    func tracksWindow(_ id: String) -> some View {
        modifier(WindowTracker(id: id))
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background {
                    VisualEffectBackground(material: .popover)
                        .clipShape(shape)
                }
                .overlay {
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

/// A behind-window blur, which respects Reduce Transparency on its own.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

private struct WindowTracker: ViewModifier {
    let id: String
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                state.openLibraryAction = { openWindow(id: WindowID.library) }
                state.windowAppeared(id)
            }
            .onDisappear {
                state.windowDisappeared(id)
            }
    }
}

/// Quill's surfaces. Light mode keeps the system colours; dark mode goes a step darker
/// than macOS's defaults, close to black, with the layers still apart.
enum Surface {
    /// Page backgrounds: Stats, History, Settings, the Firing Range, the empty editor.
    static let page = dynamic(light: .windowBackgroundColor, dark: 0x111113)
    /// Where text is typed: the editor and the practice area.
    static let editor = dynamic(light: .textBackgroundColor, dark: 0x0C0C0E)
    /// The quills sidebar (dark mode only; light keeps the system sidebar).
    static let sidebar = dynamic(light: .windowBackgroundColor, dark: 0x161619)
    /// Cards and tiles on a page.
    static let card = dynamic(light: NSColor.labelColor.withAlphaComponent(0.05), dark: 0x1C1C20)
    /// The floating tab bars.
    static let bar = dynamic(light: .windowBackgroundColor, dark: 0x1A1A1E)

    private static func dynamic(light: NSColor, dark hex: Int) -> Color {
        let darkColor = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : light
        })
    }
}
