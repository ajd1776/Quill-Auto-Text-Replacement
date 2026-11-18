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
