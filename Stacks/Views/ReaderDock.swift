import SwiftUI

/// The floating control bar at the foot of the reader.
///
/// It has two faces. Reading, it offers the four things you reach for without
/// leaving the page. In markup, it becomes the pen tray — tints, inks, note,
/// erase — and the article underneath stays fully visible, which is the point
/// of putting it here instead of in a toolbar.
struct ReaderDock: View {
    let theme: ReaderTheme
    let isMarkingUp: Bool
    @Binding var tool: MarkupTool
    @Binding var tint: HighlightTint
    @Binding var ink: InkColor
    let highlightCount: Int
    let isImmersive: Bool

    let beginMarkup: () -> Void
    let endMarkup: () -> Void
    let openTypography: () -> Void
    let openHighlights: () -> Void
    let toggleImmersive: () -> Void

    var body: some View {
        // The pen tray is wider than an iPhone in portrait. Rather than drop
        // tools or shrink them below a fingertip, the dock hugs its content
        // where it fits and scrolls where it doesn't.
        ViewThatFits(in: .horizontal) {
            items
            ScrollView(.horizontal) { items }
                .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(dockBackground)
        .clipShape(.capsule)
        .overlay(Capsule().strokeBorder(theme.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 17, y: 8)
        .animation(.snappy(duration: 0.22), value: isMarkingUp)
    }

    private var items: some View {
        HStack(spacing: isMarkingUp ? 4 : 5) {
            if isMarkingUp { markupItems } else { readingItems }
        }
    }

    private var dockBackground: some View {
        // Nearly the page's own colour over a blur: enough to read the controls
        // against a dense paragraph, translucent enough that the dock still
        // reads as floating above the text rather than cutting a hole in it.
        ZStack {
            Rectangle().fill(.regularMaterial)
            theme.background.opacity(0.72)
        }
    }

    // MARK: - Reading

    @ViewBuilder
    private var readingItems: some View {
        label("Markup", systemImage: "highlighter", isOn: false, action: beginMarkup)
            .accessibilityIdentifier("reader.markup")
        label("Aa", isOn: false, action: openTypography)
            .accessibilityIdentifier("reader.typography")
            .accessibilityLabel("Text settings")
        label("\(highlightCount)", systemImage: "sparkle", isOn: false, action: openHighlights)
            .disabled(highlightCount == 0)
            .opacity(highlightCount == 0 ? 0.4 : 1)
            .accessibilityIdentifier("reader.highlights")
            .accessibilityLabel("Highlights")
        label(
            isImmersive ? "Exit" : "Full screen",
            systemImage: isImmersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            isOn: isImmersive,
            action: toggleImmersive
        )
        .accessibilityIdentifier("reader.fullscreen")
    }

    // MARK: - Markup

    @ViewBuilder
    private var markupItems: some View {
        ForEach(HighlightTint.allCases) { option in
            swatch(
                Palette.highlight(option),
                isOn: tool == .highlight && tint == option
            ) {
                tool = .highlight
                tint = option
            }
            .accessibilityLabel("\(option.label) highlight")
        }

        divider

        ForEach(InkColor.allCases) { option in
            swatch(option.color, isOn: tool == .pen && ink == option) {
                tool = .pen
                ink = option
            }
            .accessibilityLabel("\(option.label) ink")
        }

        divider

        label("", systemImage: "text.bubble", isOn: tool == .note) { tool = .note }
            .accessibilityLabel("Add a note")
        label("", systemImage: "eraser", isOn: tool == .erase) { tool = .erase }
            .accessibilityLabel("Erase")
        label("Done", isOn: false, action: endMarkup)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.rule)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    // MARK: - Pieces

    private func label(
        _ title: String,
        systemImage: String? = nil,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(isOn ? onAccentInk : theme.inkSecondary)
            .frame(height: 30)
            .padding(.horizontal, 11)
            .background(isOn ? theme.accent : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle().strokeBorder(
                        isOn ? theme.accent : Palette.ink.opacity(0.12),
                        lineWidth: isOn ? 2 : 1
                    )
                )
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    /// Night's accent is light enough that white-on-accent disappears.
    private var onAccentInk: Color {
        theme == .night ? Color(uiColor: UIColor(hex: 0x14120F)) : Color(uiColor: UIColor(hex: 0xFFFDFA))
    }
}

/// The line of coaching under the dock while markup is on. It says what the
/// current tool does, and it says it once — it goes away as soon as the tool
/// has been used.
struct PencilHint: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(Color(uiColor: UIColor(hex: 0xF3EBE1)))
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(Color(uiColor: UIColor(hex: 0x1F1B16)).opacity(0.82), in: .capsule)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
