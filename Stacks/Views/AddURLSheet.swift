import SwiftUI

/// Paste-a-link entry. Validates as you type so a typo is obvious before the
/// fetch rather than after it fails.
struct AddURLSheet: View {
    let save: (URL, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    @State private var raw = ""
    @State private var tags = ""

    private var resolved: URL? { URL.fromUserInput(raw) }
    private var showsProblem: Bool { !raw.squeezed.isEmpty && resolved == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $raw, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .lineLimit(1...4)
                        .focused($isFocused)
                        .onSubmit(commit)
                } header: {
                    Text("Link")
                } footer: {
                    if showsProblem {
                        Label("That doesn't look like a web address.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.accent)
                    } else if let resolved {
                        Text(Post.displayHost(for: resolved))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                Section {
                    TextField("reading, research…", text: $tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Comma separated. Optional.")
                }

                if UIPasteboard.general.hasStrings {
                    Section {
                        PasteButton(payloadType: String.self) { strings in
                            guard let value = strings.first else { return }
                            Task { @MainActor in raw = value.squeezed }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
            .navigationTitle("Save a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(resolved == nil)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func commit() {
        guard let url = resolved else { return }
        let parsed = ArchiveService.normalizeTags(tags.split(separator: ",").map(String.init))
        save(url, parsed)
        dismiss()
    }
}
