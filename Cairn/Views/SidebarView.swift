import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var filter: LibraryFilter

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var index = LibraryIndex()

    // Re-extraction
    @State private var reExtraction = ReExtractionService()
    @State private var isConfirmingLibraryRebuild = false

    var body: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let value = $0 { filter = value } }
        )) {
            Section {
                // Unread is somewhere to look, not a tally to answer for —
                // no number rides along with it. The rows below count what
                // exists, which isn't the same thing as what's owed.
                row(.unread)
                row(.all, count: index.totalCount)
                row(.starred, count: index.starredCount)
                row(.archived, count: index.archivedCount)
            }

            if !index.tags.isEmpty {
                Section {
                    ForEach(index.tags) { tag in
                        row(.tag(tag.name), count: tag.count)
                    }
                } header: {
                    header("Tags")
                }
            }

            if !index.sites.isEmpty {
                Section {
                    ForEach(index.sites.prefix(24)) { site in
                        row(.site(site.name), count: site.count)
                    }
                } header: {
                    header("Sites")
                }
            }

            // A maintenance action, not a filter — it doesn't take part in
            // the list's selection, only its own tap.
            Section {
                if reExtraction.isRunning {
                    libraryRebuildProgress
                } else {
                    Button {
                        isConfirmingLibraryRebuild = true
                    } label: {
                        Label("Rebuild library", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .font(.scaled(15, weight: .medium, relativeTo: .subheadline))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.recessed)
        .navigationTitle("Cairn")
        .onAppear { index.refresh(context: context) }
        // Any save — a new post, a tag edit, a sync from another device —
        // changes what the sidebar should show.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            index.refresh(context: context)
        }
        .confirmationDialog(
            "Rebuild the library from saved pages?",
            isPresented: $isConfirmingLibraryRebuild,
            titleVisibility: .visible
        ) {
            Button("Rebuild") { reExtraction.reExtractLibrary(in: context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every archived post is rebuilt from the page it was saved from. Posts saved before that page was kept are left untouched, and no highlight is removed without asking first.")
        }
        .alert(
            "Rebuild complete",
            isPresented: Binding(
                get: { reExtraction.lastSummary != nil },
                set: { if !$0 { reExtraction.dismissSummary() } }
            ),
            presenting: reExtraction.lastSummary
        ) { summary in
            Button("OK", role: .cancel) {}
            if summary.skippedAtRisk > 0 {
                Button("Include those too", role: .destructive) {
                    reExtraction.reExtractLibrary(in: context, dropAtRiskHighlights: true)
                }
            }
        } message: { summary in
            Text(summaryText(summary))
        }
    }

    private var libraryRebuildProgress: some View {
        HStack(spacing: 11) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rebuilding…")
                    .font(.scaled(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                if let progress = reExtraction.progress {
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.scaled(12, relativeTo: .caption))
                        .foregroundStyle(Palette.inkTertiary)
                }
            }

            Spacer(minLength: 6)

            Button("Cancel") { reExtraction.cancel() }
                .font(.scaled(13, weight: .medium, relativeTo: .footnote))
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
        }
        .padding(.vertical, 2)
    }

    /// Turns a finished (or cancelled) pass into the sentence the alert shows.
    private func summaryText(_ summary: ReExtractionService.LibrarySummary) -> String {
        var parts: [String] = []
        if summary.cancelled { parts.append("Cancelled partway through.") }
        parts.append("\(summary.rebuilt) post\(summary.rebuilt == 1 ? "" : "s") rebuilt.")
        if summary.skippedNoSource > 0 {
            parts.append("\(summary.skippedNoSource) skipped — no saved page to rebuild from.")
        }
        if summary.skippedAtRisk > 0 {
            parts.append("\(summary.skippedAtRisk) skipped — \(summary.highlightsAtRisk) highlight\(summary.highlightsAtRisk == 1 ? "" : "s") couldn't be matched to the rebuilt text.")
        }
        if summary.highlightsReanchored > 0 {
            parts.append("\(summary.highlightsReanchored) highlight\(summary.highlightsReanchored == 1 ? "" : "s") moved to their new spot.")
        }
        if summary.highlightsDropped > 0 {
            parts.append("\(summary.highlightsDropped) highlight\(summary.highlightsDropped == 1 ? "" : "s") couldn't be matched and \(summary.highlightsDropped == 1 ? "was" : "were") removed.")
        }
        return parts.joined(separator: " ")
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.scaled(11, weight: .semibold, relativeTo: .caption2))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Palette.inkTertiary)
    }

    private func row(_ target: LibraryFilter, count: Int? = nil) -> some View {
        let isSelected = filter == target

        return HStack(spacing: 11) {
            Image(systemName: target.symbol)
                .font(.scaled(14, relativeTo: .callout))
                .foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
                .frame(width: 20)

            Text(target.title)
                .font(.scaled(15, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? Palette.ink : Palette.inkSecondary)
                // A larger accessibility size can outgrow one line for a long
                // tag or site name; wrapping to two beats an ellipsis.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            Spacer(minLength: 6)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.scaled(12, weight: .medium, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Palette.accentSoft : .clear)
                .padding(.horizontal, 6)
        )
        .tag(target)
    }
}
