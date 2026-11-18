import SwiftUI

/// Add or remove the built-in starter packs.
struct PackGallery: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Starter Packs")
                    .font(.title2.weight(.bold))
                Text("Each pack is added as its own group, so you can switch it off or remove it at any time.")
                    .foregroundStyle(.secondary)
            }

            ForEach(StarterPack.all) { pack in
                PackCard(pack: pack)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct PackCard: View {
    let pack: StarterPack
    @Environment(AppState.self) private var state

    var body: some View {
        let installed = state.store.installedGroup(for: pack)

        HStack(alignment: .top, spacing: 14) {
            SnippetIcon(symbol: pack.icon, color: pack.color.color, size: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(pack.name).font(.headline)
                    Text("\(pack.entries.count) snippets")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(pack.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(pack.entries.prefix(3), id: \.trigger) { entry in
                        let sample = TokenRenderer.render(entry.text, clipboard: "").text
                        Text("\(entry.trigger) → \(sample)")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            Spacer(minLength: 8)

            if installed != nil {
                Button("Remove", role: .destructive) {
                    state.store.uninstall(pack)
                }
                .help("Removes the group and its snippets")
            } else {
                Button("Add") {
                    state.store.install(pack)
                }
                .primaryActionStyle()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if installed != nil {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(pack.color.color.opacity(0.6), lineWidth: 1.5)
            }
        }
    }
}
