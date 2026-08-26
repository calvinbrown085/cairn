import SwiftUI
import PDFKit

/// Shows a PDF post the way PDFKit renders it: pages, not reflowable prose.
///
/// That's deliberate. The rest of the reader (`ReaderView`, `ArticleBlockView`)
/// works over `ArticleContent` blocks extracted from HTML — turning a PDF into
/// that same shape would mean reflowing text that was laid out for a fixed
/// page, and it would lie about what the file actually is. A PDF stays a PDF;
/// this view is what makes it readable rather than merely stored.
///
/// Highlighting does not work here. `Highlight` anchors to a block index and a
/// character range within that block's plain text (see `Highlight` in
/// `Post.swift`), and a PDF has no blocks — there is nothing for that anchor
/// to name. `limitationNotice` says so plainly, once, rather than letting a
/// highlight gesture do nothing and leave someone wondering if it worked.
struct PDFReaderView: View {
    @Bindable var post: Post

    @State private var document: PDFDocument?
    @State private var didFailToLoad = false

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    header
                    PDFKitView(document: document)
                    limitationNotice
                }
            } else if didFailToLoad {
                ReaderStatusView(
                    symbol: "exclamationmark.triangle",
                    headline: "Couldn't open this PDF",
                    detail: "The file may be damaged.",
                    isBusy: false
                )
            } else {
                ReaderStatusView(
                    symbol: "doc.richtext",
                    headline: "Opening…",
                    detail: post.title,
                    isBusy: true
                )
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(post.host.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: post.id) { load() }
    }

    private func load() {
        guard let data = post.pdfData else {
            didFailToLoad = true
            return
        }
        document = PDFDocument(data: data)
        didFailToLoad = document == nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title)
                .font(.scaled(20, weight: .bold, design: .serif, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if let author = post.author {
                    Text(author)
                    Text("·")
                }
                if let pageCount = post.pdfPageCount {
                    Text("\(pageCount) page\(pageCount == 1 ? "" : "s")")
                }
            }
            .font(.scaled(11.5, weight: .medium, relativeTo: .caption2))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// States, once, what this view cannot yet do — see the type comment.
    private var limitationNotice: some View {
        Label("Highlighting isn't available in PDFs yet", systemImage: "highlighter")
            .font(.scaled(11.5, weight: .medium, relativeTo: .caption2))
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.recessed)
    }
}

/// Bridges PDFKit's own view into SwiftUI. `PDFView` already handles
/// scrolling, zooming, and page layout; reimplementing any of that in SwiftUI
/// would be pure risk for no benefit.
private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
