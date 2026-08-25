import SwiftUI
import SwiftData

/// The note attached to one marked passage, with the passage above it so you
/// can see what you are annotating while you write.
struct NoteSheet: View {
    let highlight: Highlight

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(highlight.text)
                    .font(.scaled(16, design: .serif, relativeTo: .callout))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .lineLimit(4)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(Palette.highlight(highlight.tint), in: .rect(cornerRadius: 4))

                TextField("What struck you about this?", text: $text, axis: .vertical)
                    .font(.scaled(16, relativeTo: .callout))
                    .lineLimit(2...5)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Palette.card, in: .rect(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Palette.rule, lineWidth: 0.5)
                    )

                HStack(spacing: 9) {
                    ForEach(HighlightTint.allCases) { option in
                        Button {
                            highlight.tint = option
                            try? context.save()
                        } label: {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Palette.highlight(option))
                                .frame(height: 38)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            highlight.tint == option ? Palette.ink : Palette.ink.opacity(0.1),
                                            lineWidth: highlight.tint == option ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                    }
                }

                Text("Notes and ink sync with the highlight through iCloud, anchored to the sentence — not to a pixel — so they survive a font or theme change.")
                    .font(.scaled(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineSpacing(2)

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.recessed)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: commit)
                }
            }
            .onAppear {
                text = highlight.note ?? ""
                isFocused = true
            }
        }
    }

    private func commit() {
        let value = text.squeezed
        highlight.note = value.isEmpty ? nil : value
        try? context.save()
        dismiss()
    }
}
