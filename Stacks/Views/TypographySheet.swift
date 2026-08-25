import SwiftUI

/// Reader typography controls. Changes apply live behind the sheet and sync to
/// the other device through iCloud's key-value store.
struct TypographySheet: View {
    @Environment(ReadingPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Typeface", selection: $preferences.family) {
                        ForEach(ReaderFontFamily.allCases) { family in
                            Text(family.label)
                                .font(.system(size: 15, design: family.design))
                                .tag(family)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    stepper(
                        "Text size",
                        value: $preferences.bodySize,
                        range: ReadingPreferences.bodySizeRange,
                        step: 1,
                        format: { "\(Int($0))pt" }
                    )

                    stepper(
                        "Line spacing",
                        value: $preferences.lineSpacingRatio,
                        range: ReadingPreferences.lineSpacingRange,
                        step: 0.05,
                        format: { String(format: "%.2f", $0) }
                    )

                    stepper(
                        "Column width",
                        value: $preferences.measure,
                        range: ReadingPreferences.measureRange,
                        step: 40,
                        format: { "\(Int($0))pt" }
                    )
                } header: {
                    Text("Measure")
                } footer: {
                    Text("A narrower column is easier to track line to line. Column width only takes effect where there's room for it.")
                }

                Section {
                    preview
                }

                Section {
                    Button("Reset to defaults") {
                        withAnimation { preferences.resetToDefaults() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.recessed)
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(format(value.wrappedValue))
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.secondary)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private var preview: some View {
        let typography = preferences.typography
        let theme = preferences.theme

        return VStack(alignment: .leading, spacing: typography.lineSpacing) {
            Text("The Cost of Abstraction")
                .font(typography.font(size: typography.headingSize(level: 2), weight: .bold))
                .foregroundStyle(theme.ink)

            Text("Every layer you add buys you something and costs you something. The trick is knowing which is which before you are three layers deep.")
                .font(typography.body)
                .foregroundStyle(theme.ink)
                .lineSpacing(typography.lineSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.background, in: .rect(cornerRadius: 10))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}
