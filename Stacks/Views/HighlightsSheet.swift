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

    private var highlights: [Highlight] { post.sortedHighlights }

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty { empty } else { list }
            }
            .background(Palette.recessed)
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingNote) { highlight in
                NoteSheet(highlight: highlight)
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(highlights) { highlight in
                    card(highlight)
                }
            }
            .padding(16)
        }
    }

    private func card(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(highlight.text)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Palette.highlight(highlight.tint), in: .rect(cornerRadius: 4))

            if let note = highlight.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(highlight.createdAt, format: .relative(presentation: .named))
                    .font(.system(size: 10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(Palette.inkTertiary)

                Spacer(minLength: 0)

                Button(highlight.note == nil ? "Note" : "Edit note") {
                    editingNote = highlight
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .buttonStyle(.plain)

                Button("Delete") {
                    context.delete(highlight)
                    try? context.save()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.rule, lineWidth: 0.5)
        )
        .contentShape(.rect)
        .onTapGesture {
            jumpTo(highlight)
            dismiss()
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

    private var empty: some View {
        VStack(spacing: 9) {
            Image(systemName: "highlighter")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.inkTertiary)

            Text("Nothing marked yet")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.ink)

            Text("Tap Markup in the reader, then tap a sentence — or draw on it with Apple Pencil.")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
