import SwiftUI

/// Reader typography controls. Changes apply live behind the sheet and sync to
/// the other device through iCloud's key-value store.
struct TypographySheet: View {
    @Environment(ReadingPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    // The +/- nudge buttons hold a font glyph at a fixed size; scale the box
    // along with it so accessibility text doesn't outgrow its button.
    @ScaledMetric(relativeTo: .footnote) private var nudgeWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .footnote) private var nudgeHeight: CGFloat = 30

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Typeface", selection: $preferences.family) {
                        ForEach(ReaderFontFamily.allCases) { family in
                            Text(family.label)
                                .font(.scaled(15, design: family.design, relativeTo: .subheadline))
                                .tag(family)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 0) {
                        stepper(
                            "Text size",
                            value: $preferences.bodySize,
                            range: ReadingPreferences.bodySizeRange,
                            step: 1,
                            format: { "\(Int($0))pt" }
                        )
                        hairline
                        stepper(
                            "Line spacing",
                            value: $preferences.lineSpacingRatio,
                            range: ReadingPreferences.lineSpacingRange,
                            step: 0.05,
                            format: { String(format: "%.2f", $0) }
                        )
                        hairline
                        stepper(
                            "Column width",
                            value: $preferences.measure,
                            range: ReadingPreferences.measureRange,
                            step: 40,
                            format: { "\(Int($0))pt" }
                        )
                        hairline

                        Text("A narrower column is easier to track line to line. Changes apply live and sync to your other device.")
                            .font(.scaled(12.5, relativeTo: .caption))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                    .background(Palette.card, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Palette.rule, lineWidth: 0.5)
                    )

                    preview

                    Button("Reset to defaults") {
                        withAnimation { preferences.resetToDefaults() }
                    }
                    .font(.scaled(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.card, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Palette.rule, lineWidth: 0.5)
                    )
                }
                .padding(16)
            }
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

    private var hairline: some View {
        Rectangle().fill(Palette.rule).frame(height: 0.5)
    }

    /// A label, the current value, and a joined −／+ pair. A `Stepper` would do
    /// the job, but its own label handling fights a right-aligned readout.
    private func stepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.scaled(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)

            Spacer(minLength: 4)

            Text(format(value.wrappedValue))
                .font(.scaled(13, weight: .medium, relativeTo: .footnote).monospacedDigit())
                .foregroundStyle(Palette.inkTertiary)
                .frame(minWidth: 44, alignment: .trailing)

            HStack(spacing: 0) {
                nudge("minus", enabled: value.wrappedValue > range.lowerBound) {
                    value.wrappedValue = (value.wrappedValue - step).clamped(to: range)
                }
                Rectangle().fill(Palette.rule).frame(width: 0.5, height: nudgeHeight)
                nudge("plus", enabled: value.wrappedValue < range.upperBound) {
                    value.wrappedValue = (value.wrappedValue + step).clamped(to: range)
                }
            }
            .background(Palette.recessed, in: .rect(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityValue(format(value.wrappedValue))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func nudge(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.scaled(13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(enabled ? Palette.ink : Palette.inkTertiary.opacity(0.5))
                .frame(width: nudgeWidth, height: nudgeHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Decrease" : "Increase")
    }

    private var preview: some View {
        let typography = preferences.typography
        let theme = preferences.theme

        return VStack(alignment: .leading, spacing: 9) {
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
        .background(theme.background, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.rule, lineWidth: 0.5)
        )
    }
}
