import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import VisionKit
import PDFKit
import QuickLook
import CryptoKit

struct RecordsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var filter = "All"
    @State private var adding = false
    let filters = ["All", "Needs review", "Notes", "Labs", "Imaging", "Procedure", "Scan", "Recording"]
    var filtered: [MedicalRecord] {
        store.records.filter { record in
            (filter == "All" || (filter == "Needs review" ? record.needsReview : record.kind == filter)) &&
            (query.isEmpty || (record.title + " " + record.provider + " " + record.tags.joined(separator: " ") + " " + record.text).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        Page {
            Text("Your history, all in one place.").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(filters, id: \.self) { item in
                    Button { filter = item } label: { Text(item).font(.subheadline.weight(.medium)).padding(.horizontal, 15).padding(.vertical, 10).background(filter == item ? RevaTheme.accent : RevaTheme.surface, in: Capsule()).foregroundStyle(filter == item ? RevaTheme.buttonText : .primary) }.accessibilityAddTraits(filter == item ? .isSelected : [])
                } }
            }
            Text("\(filtered.count) \(filtered.count == 1 ? "record" : "records")").font(.caption).foregroundStyle(.secondary)
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query.isEmpty ? filter : query)
                Button("Add a record") { adding = true }.buttonStyle(PrimaryButtonStyle())
            } else {
                RevaCard {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider() }
                        NavigationLink { RecordDetailView(id: record.id) } label: { RecordRow(record: record) }.buttonStyle(.plain)
                    }
                }
            }
        }.navigationTitle("Records").searchable(text: $query, prompt: "Search records, dates, or details")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add record") } }
            .sheet(isPresented: $adding) { NavigationStack { AddRecordView() } }
    }
}

struct RecordDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    var sourcePage: Int = 1
    @State private var editing = false
    @State private var deleting = false
    @State private var original = false
    var body: some View {
        Group {
            if let record = store.record(id) {
                Page {
                    HStack { IconTile(symbol: record.symbol); Spacer(); ModeBadge(text: record.isDemo ? "SYNTHETIC RECORD" : "SAVED ON DEVICE") }
                    Text(record.title).font(.title.bold())
                    DetailLine(symbol: "calendar", text: RevaDate.display(record.date))
                    DetailLine(symbol: "building.2", text: record.provider)
                    if record.needsReview { StatusNotice(title: "Review the source", message: "Some text or dates need confirmation. Compare the original before using this record in a visit.", symbol: "exclamationmark.circle") }
                    RevaCard {
                        Label(hasAuthoredSummary(record) ? record.summaryLabel : "Local excerpt", systemImage: "text.alignleft").font(.headline).foregroundStyle(RevaTheme.accent)
                        Text(record.summary.isEmpty ? "No readable text yet. Edit the extraction to add a summary." : record.summary).font(.body).textSelection(.enabled)
                        Text(hasAuthoredSummary(record) ? "Prepared from fictional source material for this demo." : "An automatic excerpt of extracted text. Gemini is not connected.").font(.caption).foregroundStyle(.secondary)
                    }
                    if store.sourceURL(record) != nil {
                        Button { original = true } label: { Label(sourcePage > 0 ? "Open original · page \(sourcePage)" : "Open original", systemImage: "doc.richtext") }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                    }
                    if !record.notes.isEmpty { RevaCard { Text("Notes").font(.headline); Text(record.notes).textSelection(.enabled) } }
                    RevaCard {
                        DisclosureGroup("Full extracted text") { Text(record.text.isEmpty ? "No text extracted. Add a correction using Edit." : record.text).font(.subheadline).textSelection(.enabled).padding(.top, 10) }
                    }
                    Button("Edit record & review text") { editing = true }.buttonStyle(PrimaryButtonStyle())
                    Button("Delete record", role: .destructive) { deleting = true }.frame(maxWidth: .infinity).padding(.top, 5)
                }
                .sheet(isPresented: $editing) { NavigationStack { RecordEditorView(record: record) } }
                .sheet(isPresented: $original) { if let url = store.sourceURL(record) { SourcePreview(url: url, page: sourcePage, title: record.title) } }
            } else { ContentUnavailableView("Source no longer available", systemImage: "doc.questionmark", description: Text("This record was deleted. Regenerate the visit brief to update its evidence.")) }
        }.navigationTitle("Record").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this record from your local history? Existing briefs will be marked out of date.", isPresented: $deleting, titleVisibility: .visible) { Button("Delete record", role: .destructive) { if store.perform({ try store.deleteRecord(id) }) { dismiss() } } }
    }
    /// A fictional record keeps its origin badge after a text correction, but its authored demo summary is replaced by a local excerpt; label what is shown.
    private func hasAuthoredSummary(_ record: MedicalRecord) -> Bool { record.isDemo && record.summary != ReportEngine.localExcerpt(record.text) }
}
struct RecordEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let original: MedicalRecord
    @State private var record: MedicalRecord
    @State private var reviewed = false
    init(record: MedicalRecord) { original = record; _record = State(initialValue: record) }
    private var textChanged: Bool { record.text != original.text }
    private var textPresent: Bool { !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        Form {
            Section("Record details") { TextField("Title", text: $record.title); TextField("Provider", text: $record.provider); DatePicker("Record date", selection: Binding(get: { RevaDate.parse(record.date) }, set: { record.date = RevaDate.day($0) }), displayedComponents: .date) }
            Section { TextEditor(text: $record.text).frame(minHeight: 220) } header: { Text("Extracted text") } footer: { Text("Keep the original wording, values, and units. Changing text refreshes the local excerpt and marks existing briefs out of date. Check source details again after a correction. Title, date, and notes edits keep the summary.") }
            Section("Your notes") { TextEditor(text: $record.notes).frame(minHeight: 100) }
            Section { Toggle("I checked the text against the source", isOn: $reviewed) }
        }.navigationTitle("Edit record").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    }
    private func save() {
        var revised = record
        revised.isDemo = original.isDemo // Fictional origin describes the source, not whether the user edited it.
        if textChanged {
            revised.summary = ReportEngine.localExcerpt(record.text)
            revised.pageTexts = nil // A manual whole-document correction no longer claims the original page segmentation.
            revised.status = reviewed && textPresent ? "ready" : "needsReview"
        } else if reviewed, textPresent, original.status == "needsReview" {
            revised.status = "ready" // Explicit confirmation clears the review state; summary and pages stay; the source version advances.
        }
        if store.perform({ try store.save(revised) }) { dismiss() }
    }
}

struct AddRecordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var files = false
    @State private var scanner = false
    @State private var sample = false
    @State private var photo: PhotosPickerItem?
    @State private var imported: ImportedDocument?
    @State private var working = false
    @State private var importError: String?
    @State private var title = ""
    @State private var text = ""
    @State private var recordDate = Date()
    @State private var verified = false
    @State private var manual = false
    private let importer = DocumentImportService()
    var body: some View {
        Page {
            if working {
                RevaCard { ProgressView(); Text("Reading your document").font(.headline); Text("Extracting text on this device. Scanned pages may take a moment.").foregroundStyle(.secondary) }
            } else if let imported {
                preview(imported)
            } else if manual {
                RevaCard { TextField("Record title", text: $title).font(.headline); TextEditor(text: $text).frame(minHeight: 240); Button("Review note") { imported = ImportedDocument(filename: "note.txt", mimeType: "text/plain", data: Data(text.utf8), text: text, warnings: [], pageCount: 1); manual = false }.buttonStyle(PrimaryButtonStyle()).disabled(title.isEmpty || text.isEmpty) }
            } else {
                Text("Bring a document.\nKeep the useful details.").font(.title2.bold())
                Text("Choose a source, review its text, and save it to your history.").foregroundStyle(.secondary)
                RevaCard {
                    Button { files = true } label: { intakeRow("Choose from Files", subtitle: "PDF, text, or image · up to 16 MB", symbol: "folder") }
                    Divider()
                    PhotosPicker(selection: $photo, matching: .images) { intakeRow("Choose a photo", subtitle: "Extract text from a saved image", symbol: "photo") }
                    Divider()
                    Button { scanner = true } label: { intakeRow("Scan a document", subtitle: DocumentScanner.isSupported ? "Use your iPhone camera" : "Camera requires a physical iPhone", symbol: "doc.viewfinder") }.disabled(!DocumentScanner.isSupported)
                    Divider()
                    Button { manual = true } label: { intakeRow("Write a note", subtitle: "Keep a detail in your own words", symbol: "square.and.pencil") }
                }.buttonStyle(.plain)
                Button { sample = true } label: { Label("Try a fictional sample", systemImage: "sparkles.rectangle.stack") }.buttonStyle(.bordered).controlSize(.large)
                StatusNotice(title: "A quick review matters", message: "Text extraction can miss or misread details. Compare dates, doses, and values with the source. The automatic summary is a local excerpt.")
            }
            if let importError { StatusNotice(title: "Couldn’t import this item", message: importError, symbol: "exclamationmark.circle") }
        }.navigationTitle(imported == nil ? "Add record" : "Review document").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .plainText, .image]) { result in
                switch result { case .success(let url): Task { await ingest(url) }; case .failure(let error): importError = error.localizedDescription }
            }
            .onChange(of: photo) { _, value in Task {
                do { guard let value, let data = try await value.loadTransferable(type: Data.self) else { return }; working = true; defer { working = false }; setImported(try await importer.ingest(imageData: data, filename: "photo.jpg")) }
                catch { importError = error.localizedDescription }
            } }
            .sheet(isPresented: $scanner) { DocumentScanner(onFinish: { images in
                scanner = false
                Task {
                    working = true; defer { working = false }
                    do {
                        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
                        let bytes = renderer.pdfData { context in for image in images { context.beginPage(); let scale = min(572/image.size.width, 752/image.size.height); let size = CGSize(width: image.size.width*scale, height: image.size.height*scale); image.draw(in: CGRect(x: (612-size.width)/2, y: (792-size.height)/2, width: size.width, height: size.height)) } }
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf"); try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }; setImported(try await importer.ingest(url: url))
                    } catch { importError = error.localizedDescription }
                }
            }, onCancel: { scanner = false }, onError: { importError = $0.localizedDescription; scanner = false }) }
            .sheet(isPresented: $sample) { NavigationStack { List {
                Button("Preparation note · text") { sample = false; if let url = Bundle.main.url(forResource: "reva-synthetic-import-preparation-note", withExtension: "txt") { Task { await ingest(url) } } }
                Button("Scanned diary · image-only PDF") { sample = false; if let url = Bundle.main.url(forResource: "reva-synthetic-symptom-diary-image-only", withExtension: "pdf") { Task { await ingest(url) } } }
                ForEach(store.records.filter { $0.isDemo && $0.sourceFilename != nil }) { record in Button(record.title) { sample = false; if let url = store.sourceURL(record) { Task { await ingest(url) } } } }
            }.navigationTitle("Fictional samples").toolbar { Button("Done") { sample = false } } } }
    }
    private func intakeRow(_ name: String, subtitle: String, symbol: String) -> some View { HStack(spacing: 14) { IconTile(symbol: symbol); VStack(alignment: .leading, spacing: 4) { Text(name).font(.headline).foregroundStyle(.primary); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0) }.padding(.vertical, 5) }
    private func ingest(_ url: URL) async {
        working = true; importError = nil; defer { working = false }
        do { setImported(try await importer.ingest(url: url)) } catch { importError = error.localizedDescription }
    }
    private func setImported(_ item: ImportedDocument) { imported = item; title = item.filename.replacingOccurrences(of: "." + (item.filename as NSString).pathExtension, with: "").replacingOccurrences(of: "-", with: " "); text = item.text; verified = false }
    private func preview(_ item: ImportedDocument) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ModeBadge(text: "ON-DEVICE EXTRACTION")
            RevaCard { TextField("Title", text: $title).font(.headline); DatePicker("Record date", selection: $recordDate, displayedComponents: .date); Text("Choose the date shown on your record.").font(.caption).foregroundStyle(.secondary) }
            ForEach(item.warnings, id: \.self) { warning in StatusNotice(title: "Check the extraction", message: warning, symbol: "exclamationmark.circle") }
            RevaCard { Text("Extracted text").font(.headline); TextEditor(text: $text).frame(minHeight: 220); Toggle("I reviewed the text against the source", isOn: $verified) }
            RevaCard { Text("Local excerpt").font(.headline); Text(ReportEngine.localExcerpt(text).isEmpty ? "No readable text. Add a transcription above or save for review." : ReportEngine.localExcerpt(text)).font(.subheadline); Text("Generated automatically on this device. No cloud model ran.").font(.caption).foregroundStyle(.secondary) }
            Button("Save to Records") {
                let name = UUID().uuidString + "-" + item.filename
                let saved = store.perform {
                    _ = try store.repository.storeAttachment(item.data, filename: name)
                    let record = MedicalRecord(title: title, kind: item.mimeType.hasPrefix("image") ? "Scan" : "Notes", provider: "Manually added", date: RevaDate.day(recordDate), text: text, summary: ReportEngine.localExcerpt(text), sourceFilename: name, mimeType: item.mimeType, pageCount: item.pageCount, status: verified && !text.isEmpty ? "ready" : "needsReview", notes: item.warnings.joined(separator: "\n"), pageTexts: text == item.text ? item.pageTexts : nil)
                    try store.save(record); store.notice = "Record saved with a local excerpt."
                }
                if saved { dismiss() }
            }.buttonStyle(PrimaryButtonStyle()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Choose another file") { imported = nil; title = ""; text = "" }.frame(maxWidth: .infinity)
        }
    }
}

struct SourcePreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var page: Int = 1
    let title: String
    var body: some View { NavigationStack {
        Group { if url.pathExtension.lowercased() == "pdf" { NativePDFView(url: url, page: page) } else { QuickLookView(url: url) } }
            .navigationTitle("Original source").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .primaryAction) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } } }
    } }
}
struct NativePDFView: UIViewRepresentable {
    let url: URL; let page: Int
    func makeUIView(context: Context) -> RevaPDFView { let view = RevaPDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateUIView(_ uiView: RevaPDFView, context: Context) { uiView.show(url: url, page: page) }
}
/// PDFKit ignores `go(to:)` before the view has a laid-out size, so the target page is applied in `layoutSubviews` and re-applied only when the URL or page changes.
final class RevaPDFView: PDFView {
    private var shownURL: URL?
    private var shownPage = 0
    private var pendingPageIndex: Int?
    private var remainingAttempts = 0
    func show(url: URL, page: Int) {
        if shownURL != url { document = PDFDocument(url: url); shownURL = url; shownPage = 0 }
        guard page != shownPage else { return }
        shownPage = page
        pendingPageIndex = min(max(0, page - 1), max(0, (document?.pageCount ?? 1) - 1))
        remainingAttempts = 3
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let index = pendingPageIndex, bounds.width > 0, bounds.height > 0, let target = document?.page(at: index) else { return }
        go(to: target)
        remainingAttempts -= 1
        if currentPage == target || remainingAttempts <= 0 { pendingPageIndex = nil }
        else { DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() } } // PDFKit may still be laying out its document; retry on the next pass, bounded.
    }
}
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL; init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
