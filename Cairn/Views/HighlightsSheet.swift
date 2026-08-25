import SwiftUI
import SwiftData

/// Every passage marked in a post, with its note. Tapping one jumps the reader
/// to that block.
struct HighlightsSheet: View {
    let post: Post
    let jumpTo: (Highlight) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                .font(.scaled(15, design: .serif, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Palette.highlight(highlight.tint), in: .rect(cornerRadius: 4))

            if let note = highlight.note, !note.isEmpty {
                Text(note)
                    .font(.scaled(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            cardFooter(highlight)
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

    /// Date, note button, and delete button. At accessibility sizes the three
    /// no longer share a row without crowding, so the date moves above the
    /// actions instead of squeezing next to them.
    @ViewBuilder
    private func cardFooter(_ highlight: Highlight) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                dateLabel(highlight)
                HStack(spacing: 14) {
                    noteButton(highlight)
                    deleteButton(highlight)
                }
            }
        } else {
            HStack(spacing: 8) {
                dateLabel(highlight)
                Spacer(minLength: 0)
                noteButton(highlight)
                deleteButton(highlight)
            }
        }
    }

    private func dateLabel(_ highlight: Highlight) -> some View {
        Text(highlight.createdAt, format: .relative(presentation: .named))
            .font(.scaled(10.5, weight: .semibold, relativeTo: .caption2))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(Palette.inkTertiary)
    }

    private func noteButton(_ highlight: Highlight) -> some View {
        Button(highlight.note == nil ? "Note" : "Edit note") {
            editingNote = highlight
        }
        .font(.scaled(12, weight: .medium, relativeTo: .caption))
        .foregroundStyle(Palette.inkSecondary)
        .buttonStyle(.plain)
    }

    private func deleteButton(_ highlight: Highlight) -> some View {
        Button("Delete") {
            context.delete(highlight)
            try? context.save()
        }
        .font(.scaled(12, weight: .medium, relativeTo: .caption))
        .foregroundStyle(Palette.accent)
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 9) {
            Image(systemName: "highlighter")
                .font(.scaled(24, weight: .light, relativeTo: .title2))
                .foregroundStyle(Palette.inkTertiary)

            Text("Nothing marked yet")
                .font(.scaled(18, weight: .semibold, design: .serif, relativeTo: .title3))
                .foregroundStyle(Palette.ink)

            Text("Tap Markup in the reader, then tap a sentence — or draw on it with Apple Pencil.")
                .font(.scaled(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 270)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
