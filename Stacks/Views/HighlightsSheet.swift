import SwiftUI
import SwiftData

/// Every passage marked in a post, with its note. Tapping one jumps the reader
/// to that block.
struct HighlightsSheet: View {
    let post: Post
    let jumpTo: (Highlight) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editingNote: Highlight?

    var body: some View {
        NavigationStack {
            List {
                ForEach(post.sortedHighlights) { highlight in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(highlight.text)
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Palette.highlight(highlight.tint), in: .rect(cornerRadius: 3))

                        if let note = highlight.note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.inkSecondary)
                                .italic()
                        }
                    }
                    .padding(.vertical, 3)
                    .listRowBackground(Palette.paper)
                    .listRowSeparatorTint(Palette.rule)
                    .contentShape(.rect)
                    .onTapGesture {
                        jumpTo(highlight)
                        dismiss()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            context.delete(highlight)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingNote = highlight
                        } label: {
                            Label("Note", systemImage: "text.bubble")
                        }
                        .tint(Palette.inkSecondary)
                    }
                    .contextMenu {
                        Picker("Colour", selection: Binding(
                            get: { highlight.tint },
                            set: { highlight.tint = $0; try? context.save() }
                        )) {
                            ForEach(HighlightTint.allCases) { tint in
                                Text(tint.label).tag(tint)
                            }
                        }
                        Button { editingNote = highlight } label: {
                            Label("Add note", systemImage: "text.bubble")
                        }
                        Button(role: .destructive) {
                            context.delete(highlight)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingNote) { highlight in
                NoteEditor(highlight: highlight)
                    .presentationDetents([.height(260)])
            }
        }
    }
}

private struct NoteEditor: View {
    let highlight: Highlight

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("What struck you about this?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = text.squeezed
                        highlight.note = value.isEmpty ? nil : value
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear { text = highlight.note ?? "" }
        }
    }
}
