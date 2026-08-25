import SwiftUI
import SwiftData

/// Paste-a-link entry. Validates as you type so a typo is obvious before the
/// fetch rather than after it fails.
struct AddURLSheet: View {
    let save: (URL, [String]) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    @State private var raw = ""
    @State private var tags = ""
    @State private var index = LibraryIndex()

    private var resolved: URL? { URL.fromUserInput(raw) }
    private var showsProblem: Bool { !raw.squeezed.isEmpty && resolved == nil }

    /// The tags already in use, most-used first — the ones worth one tap.
    private var suggestions: [String] {
        let chosen = Set(
            tags.split(separator: ",")
                .map { $0.squeezed.lowercased() }
                .filter { !$0.isEmpty }
        )
        return index.tags
            .sorted { $0.count > $1.count }
            .map(\.name)
            .filter { !chosen.contains($0.lowercased()) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field("Link") {
                        TextField("https://…", text: $raw, axis: .vertical)
                            .font(.system(size: 16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .lineLimit(1...4)
                            .focused($isFocused)
                            .onSubmit(commit)
                    } hint: {
                        Text(hintText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(showsProblem ? Palette.accent : Palette.inkTertiary)
                    }

                    field("Tags") {
                        TextField("reading, research…", text: $tags)
                            .font(.system(size: 16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } hint: {
                        if suggestions.isEmpty {
                            Text("Comma separated. Optional.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.inkTertiary)
                        } else {
                            chips
                        }
                    }

                    if UIPasteboard.general.hasStrings {
                        PasteButton(payloadType: String.self) { strings in
                            guard let value = strings.first else { return }
                            Task { @MainActor in raw = value.squeezed }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.roundedRectangle(radius: 11))
                        .tint(Palette.card)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(Palette.recessed)
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
            .onAppear {
                isFocused = true
                index.refresh(context: context)
            }
        }
    }

    private var hintText: String {
        if raw.squeezed.isEmpty { return "Paste or type a web address." }
        guard let resolved else { return "That doesn't look like a web address." }
        return Post.displayHost(for: resolved)
    }

    private var chips: some View {
        // A wrapping run of chips; `Flow` is iOS 16+ only via `Layout`, and a
        // lazy grid would give every chip the same width.
        FlowLayout(spacing: 7) {
            ForEach(suggestions, id: \.self) { tag in
                Button {
                    tags = tags.squeezed.isEmpty ? tag : tags.squeezed + ", " + tag
                } label: {
                    Text("#\(tag)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Palette.ruleStrong.opacity(0.35), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field<Content: View, Hint: View>(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder hint: () -> Hint
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Palette.inkTertiary)
                .padding(.horizontal, 4)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Palette.card, in: .rect(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Palette.rule, lineWidth: 0.5)
                )

            hint()
                .padding(.horizontal, 4)
        }
    }

    private func commit() {
        guard let url = resolved else { return }
        let parsed = ArchiveService.normalizeTags(tags.split(separator: ",").map(String.init))
        save(url, parsed)
        dismiss()
    }
}

/// Lays subviews out in rows, wrapping when the next one won't fit — what an
/// `HStack` would do if it could wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
                x = 0
            }
            current.indices.append(index)
            x += size.width + spacing
            current.width = max(current.width, x - spacing)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
