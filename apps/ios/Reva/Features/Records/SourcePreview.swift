// Purpose: Preview and share an original attachment or exported visit brief.
// Inputs: A local file URL, requested PDF page, and display title.
// Outputs: A PDFKit or Quick Look preview and the system share sheet.
// Side effects: Reads the supplied file and navigates PDF pages after layout; sharing requires a user action.

import PDFKit
import QuickLook
import SwiftUI

// MARK: - SourcePreview
/// Preview and share an original attachment or exported visit brief.
struct SourcePreview: View {
    // MARK: - Preview inputs
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var page: Int = 1
    let title: String
    // MARK: - Rendering and sharing
    var body: some View {
        NavigationStack {
            Group {
                if url.pathExtension.lowercased() == "pdf" {
                    NativePDFView(url: url, page: page)
                } else {
                    QuickLookView(url: url)
                }
            }
            .navigationTitle(title == "Visit brief" ? "Visit brief" : "Original source")
            .navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}

// MARK: - NativePDFView
/// Bridge SwiftUI updates to the PDF view without navigating before layout.
struct NativePDFView: UIViewRepresentable {
    let url: URL
    let page: Int
    // MARK: - SwiftUI bridge lifecycle
    func makeUIView(context: Context) -> RevaPDFView {
        let view = RevaPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }
    func updateUIView(_ uiView: RevaPDFView, context: Context) { uiView.show(url: url, page: page) }
}

// MARK: - RevaPDFView
/// Apply the requested PDF page after layout, with at most three layout attempts.
/// PDFKit ignores `go(to:)` before the view has a laid-out size, so the target page is applied in `layoutSubviews` and re-applied only when the URL or page changes.
final class RevaPDFView: PDFView {
    // MARK: - Loaded source and bounded navigation state
    private var shownURL: URL?
    private var shownPage = 0
    private var pendingPageIndex: Int?
    private var remainingAttempts = 0
    // MARK: - Source and page updates
    /// Schedule navigation only when the source URL or requested page changes.
    func show(url: URL, page: Int) {
        if shownURL != url {
            document = PDFDocument(url: url)
            shownURL = url
            shownPage = 0
        }
        guard page != shownPage else { return }
        shownPage = page
        pendingPageIndex = min(max(0, page - 1), max(0, (document?.pageCount ?? 1) - 1))
        remainingAttempts = 3
        setNeedsLayout()
    }
    // MARK: - Layout-dependent page navigation
    /// Wait for nonzero bounds before applying the pending page, with a bounded retry count.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let index = pendingPageIndex, bounds.width > 0, bounds.height > 0,
            let target = document?.page(at: index)
        else { return }
        go(to: target)
        remainingAttempts -= 1
        if currentPage == target || remainingAttempts <= 0 {
            pendingPageIndex = nil
        } else {
            DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() }
        }  // PDFKit may still be laying out its document; retry on the next pass, bounded.
    }
}

// MARK: - QuickLookView
/// Bridge one local non-PDF attachment into the system preview controller.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    // MARK: - System preview lifecycle
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    // MARK: - Single-item preview data source
    /// Keep the supplied URL alive for the system preview controller.
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
