import SwiftUI
import SwiftData

/// Adds and removes tags on a post, suggesting tags already in use so the
/// vocabulary stays small instead of sprouting near-duplicates.
struct TagSheet: View {
    let post: Post

    @Environment(ArchiveService.self) private var archive
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var tags: [String] = []
    @State private var index = LibraryIndex()

    private var suggestions: [String] {
        let applied = Set(tags.map { $0.lowercased() })
        let typed = draft.squeezed.lowercased()
        return index.tags
            .map(\.name)
            .filter { !applied.contains($0.lowercased()) }
            .filter { typed.isEmpty || $0.lowercased().contains(typed) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("New tag", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(commitDraft)

                        Button("Add", action: commitDraft)
                            .disabled(draft.squeezed.isEmpty)
                    }
                }

                if !tags.isEmpty {
                    Section("On this post") {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.accent)
                                Text(tag)
                                Spacer()
                                Button {
                                    withAnimation { tags.removeAll { $0 == tag } }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(tag)")
                            }
                        }
                    }
                }

                if !suggestions.isEmpty {
                    Section("Already in use") {
                        ForEach(suggestions.prefix(12), id: \.self) { tag in
                            Button {
                                withAnimation { add(tag) }
                            } label: {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(Palette.ink)
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        archive.setTags(tags, on: post)
                        dismiss()
                    }
                }
            }
            .onAppear {
                tags = post.tagNames
                index.refresh(context: context)
            }
        }
    }

    private func commitDraft() {
        let value = draft.squeezed
        guard !value.isEmpty else { return }
        withAnimation { add(value) }
        draft = ""
    }

    private func add(_ tag: String) {
        tags = ArchiveService.normalizeTags(tags + [tag])
    }
}
