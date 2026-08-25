import SwiftUI

/// How the library is ordered and drawn. Everything here changes what you are
/// looking at rather than what is stored, so it opens from the chip strip
/// instead of hiding in settings.
struct SortSheet: View {
    @Binding var sort: LibrarySort

    @Environment(ReadingPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Sort") {
                        ForEach(Array(LibrarySort.allCases.enumerated()), id: \.element.id) { position, option in
                            Button {
                                sort = option
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    if sort == option {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)

                            if position < LibrarySort.allCases.count - 1 { hairline }
                        }
                    }

                    section("Layout") {
                        Picker("Layout", selection: $preferences.libraryStyle) {
                            ForEach(LibraryStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(12)

                        hairline

                        Toggle(isOn: $preferences.groupBySite) {
                            Text("Group by site")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.ink)
                        }
                        .tint(Palette.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    Text("Cards lead with a cover and the article's opening lines. Rows fit more of the library on screen at once.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.inkTertiary)
                        .lineSpacing(2)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Palette.recessed)
            .navigationTitle("Sort & group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Palette.inkTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) { content() }
                .background(Palette.card, in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Palette.rule, lineWidth: 0.5)
                )
        }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.rule).frame(height: 0.5)
    }
}
