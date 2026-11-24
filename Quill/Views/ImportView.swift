import SwiftUI

/// Lets people choose which text replacements to bring into Quill.
struct ImportView: View {
    let session: ImportSession

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String>

    init(session: ImportSession) {
        self.session = session
        _chosen = State(initialValue: Set(session.candidates.filter { !$0.isAlreadyInQuill }.map(\.id)))
    }

    private var importable: [ImportSession.Candidate] {
        session.candidates.filter { !$0.isAlreadyInQuill }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Text Replacements")
                    .font(.title2.weight(.semibold))
                Text("Found \(session.candidates.count) in \(session.source). Choose the ones to add to Quill.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            List {
                ForEach(session.candidates) { candidate in
                    Toggle(isOn: binding(for: candidate)) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(candidate.shortcut)
                                .font(.body.monospaced().weight(.semibold))
                                .frame(minWidth: 80, alignment: .leading)
                            Text(candidate.phrase.replacingOccurrences(of: "\n", with: " "))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if candidate.isAlreadyInQuill {
                                Text("Already in Quill")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(candidate.isAlreadyInQuill)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 220)
            .padding(.horizontal, 20)

            Text("Quill expands before macOS does, so leaving these in System Settings won't cause double expansion. You can remove them there later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            HStack {
                Button(chosen.count == importable.count ? "Deselect All" : "Select All") {
                    chosen = chosen.count == importable.count ? [] : Set(importable.map(\.id))
                }
                .disabled(importable.isEmpty)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(chosen.count == 1 ? "Import 1 Quill" : "Import \(chosen.count) Quills") {
                    state.finishImport(session.candidates.filter { chosen.contains($0.id) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 540, height: 460)
    }

    private func binding(for candidate: ImportSession.Candidate) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(candidate.id) },
            set: { isOn in
                if isOn { chosen.insert(candidate.id) } else { chosen.remove(candidate.id) }
            }
        )
    }
}
