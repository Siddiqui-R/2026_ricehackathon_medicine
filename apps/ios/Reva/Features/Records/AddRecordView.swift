// Purpose: Import a document, photo, scan, or note and review its extracted text.
// Inputs: Files, Photos, camera scan pages, manual text, or bundled fictional samples.
// Outputs: A reviewed MedicalRecord with its original attachment and local excerpt.
// Side effects: Reads sources, performs local extraction, writes attachments/state, and optionally requests AI.

import CryptoKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

// MARK: - AddRecordView
/// Import a document, photo, scan, or note and review its extracted text.
struct AddRecordView: View {
    // MARK: - Inputs and view state

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
    @State private var loggingSymptoms = false
    private let importer = DocumentImportService()
    // MARK: - Rendering and navigation
    var body: some View {
        Page {
            if working {
                RevaCard {
                    ProgressView()
                    Text("Reading your document").font(.headline)
                    Text("Extracting text on this device. Scanned pages may take a moment.").foregroundStyle(
                        .secondary)
                }
            } else if let imported {
                preview(imported)
            } else if manual {
                RevaCard {
                    TextField("Record title", text: $title).font(.headline)
                    TextEditor(text: $text).frame(minHeight: 240)
                    Button("Review note") {
                        imported = ImportedDocument(
                            filename: "note.txt", mimeType: "text/plain", data: Data(text.utf8), text: text,
                            warnings: [], pageCount: 1)
                        manual = false
                    }.buttonStyle(PrimaryButtonStyle()).disabled(title.isEmpty || text.isEmpty)
                }
            } else {
                Text("Bring a document.\nKeep the useful details.").font(.title2.bold())
                Text("Choose a source, review its text, and save it to your history.").foregroundStyle(
                    .secondary)
                RevaCard {
                    Button {
                        files = true
                    } label: {
                        intakeRow(
                            "Choose from Files", subtitle: "PDF, text, or image · up to 16 MB",
                            symbol: "folder")
                    }
                    Divider()
                    PhotosPicker(selection: $photo, matching: .images) {
                        intakeRow(
                            "Choose a photo", subtitle: "Extract text from a saved image", symbol: "photo")
                    }
                    Divider()
                    Button {
                        scanner = true
                    } label: {
                        intakeRow(
                            "Scan a document",
                            subtitle: DocumentScanner.isSupported
                                ? "Use your iPhone camera" : "Camera requires a physical iPhone",
                            symbol: "doc.viewfinder")
                    }.disabled(!DocumentScanner.isSupported)
                    Divider()
                    Button {
                        manual = true
                    } label: {
                        intakeRow(
                            "Write a note", subtitle: "Keep a detail in your own words",
                            symbol: "square.and.pencil")
                    }
                    Divider()
                    Button {
                        loggingSymptoms = true
                    } label: {
                        intakeRow(
                            "Log symptoms", subtitle: "Record what you felt and when",
                            symbol: "heart.text.clipboard")
                    }
                }.buttonStyle(.plain)
                Button {
                    sample = true
                } label: {
                    Label("Try a fictional sample", systemImage: "sparkles.rectangle.stack")
                }.buttonStyle(.bordered).controlSize(.large)
                StatusNotice(
                    title: "A quick review matters",
                    message:
                        "Text extraction can miss or misread details. Compare dates, doses, and values with the source. The automatic summary is a local excerpt."
                )
            }
            if let importError {
                StatusNotice(
                    title: "Couldn’t import this item", message: importError, symbol: "exclamationmark.circle"
                )
            }
        }.navigationTitle(imported == nil ? "Add record" : "Review document").navigationBarTitleDisplayMode(
            .inline
        )
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .sheet(isPresented: $loggingSymptoms) { NavigationStack { SymptomEntryEditorView() } }
        .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .plainText, .image]) { result in
            switch result {
            case .success(let url): Task { await ingest(url) }
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, value in
            Task {
                do {
                    guard let value, let data = try await value.loadTransferable(type: Data.self) else {
                        return
                    }
                    working = true
                    defer { working = false }
                    setImported(try await importer.ingest(imageData: data, filename: "photo.jpg"))
                } catch { importError = error.localizedDescription }
            }
        }
        .sheet(isPresented: $scanner) {
            DocumentScanner(
                onFinish: { images in
                    scanner = false
                    Task {
                        working = true
                        defer { working = false }
                        do {
                            let renderer = UIGraphicsPDFRenderer(
                                bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
                            let bytes = renderer.pdfData { context in
                                for image in images {
                                    context.beginPage()
                                    let scale = min(572 / image.size.width, 752 / image.size.height)
                                    let size = CGSize(
                                        width: image.size.width * scale, height: image.size.height * scale)
                                    image.draw(
                                        in: CGRect(
                                            x: (612 - size.width) / 2, y: (792 - size.height) / 2,
                                            width: size.width, height: size.height))
                                }
                            }
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                                UUID().uuidString + ".pdf")
                            try bytes.write(to: url)
                            defer { try? FileManager.default.removeItem(at: url) }
                            setImported(try await importer.ingest(url: url))
                        } catch { importError = error.localizedDescription }
                    }
                }, onCancel: { scanner = false },
                onError: {
                    importError = $0.localizedDescription
                    scanner = false
                })
        }
        .sheet(isPresented: $sample) {
            NavigationStack {
                List {
                    Button("Preparation note · text") {
                        sample = false
                        if let url = Bundle.main.url(
                            forResource: "reva-synthetic-import-preparation-note", withExtension: "txt")
                        {
                            Task { await ingest(url) }
                        }
                    }
                    Button("Scanned symptom note · image-only PDF") {
                        sample = false
                        if let url = Bundle.main.url(
                            forResource: "reva-synthetic-symptom-diary-image-only", withExtension: "pdf")
                        {
                            Task { await ingest(url) }
                        }
                    }
                    ForEach(store.records.filter { $0.isDemo && $0.sourceFilename != nil }) { record in
                        Button(record.title) {
                            sample = false
                            if let url = store.sourceURL(record) { Task { await ingest(url) } }
                        }
                    }
                }.navigationTitle("Fictional samples").toolbar { Button("Done") { sample = false } }
            }
        }
    }
    // MARK: - Import choice presentation
    private func intakeRow(_ name: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5)
    }
    // MARK: - Source ingestion
    /// Extract locally and surface errors without creating a saved record before review.
    private func ingest(_ url: URL) async {
        working = true
        importError = nil
        defer { working = false }
        do { setImported(try await importer.ingest(url: url)) } catch {
            importError = error.localizedDescription
        }
    }
    /// Reset review confirmation whenever a newly extracted source replaces the draft.
    private func setImported(_ item: ImportedDocument) {
        imported = item
        title = item.filename.replacingOccurrences(
            of: "." + (item.filename as NSString).pathExtension, with: ""
        ).replacingOccurrences(of: "-", with: " ")
        text = item.text
        verified = false
    }
    // MARK: - Review and save
    /// Save original bytes with the reviewed text; request connected AI only after the record exists.
    private func preview(_ item: ImportedDocument) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ModeBadge(text: "ON-DEVICE EXTRACTION")
            RevaCard {
                TextField("Title", text: $title).font(.headline)
                DatePicker("Record date", selection: $recordDate, displayedComponents: .date).environment(
                    \.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
                Text("Choose the date shown on your record.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(item.warnings, id: \.self) { warning in
                StatusNotice(
                    title: "Check the extraction", message: warning, symbol: "exclamationmark.circle")
            }
            RevaCard {
                Text("Extracted text").font(.headline)
                TextEditor(text: $text).frame(minHeight: 220)
                Toggle("I reviewed the text against the source", isOn: $verified)
            }
            RevaCard {
                Text("Local excerpt").font(.headline)
                Text(
                    ReportEngine.localExcerpt(text).isEmpty
                        ? "No readable text. Add a transcription above or save for review."
                        : ReportEngine.localExcerpt(text)
                ).font(.subheadline)
                Text("Generated automatically on this device. No cloud model ran.").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save to Records") {
                let name = UUID().uuidString + "-" + item.filename
                let saved = store.perform {
                    _ = try store.repository.storeAttachment(item.data, filename: name)
                    let record = MedicalRecord(
                        title: title, kind: item.mimeType.hasPrefix("image") ? "Scan" : "Notes",
                        provider: "Manually added", date: RevaDate.day(recordDate), text: text,
                        summary: ReportEngine.localExcerpt(text), sourceFilename: name,
                        mimeType: item.mimeType, pageCount: item.pageCount,
                        status: verified && !text.isEmpty ? "ready" : "needsReview",
                        notes: item.warnings.joined(separator: "\n"),
                        pageTexts: text == item.text ? item.pageTexts : nil)
                    try store.save(record)
                    store.notice = "Record saved with a local excerpt."
                    if store.useConnectedAI && !record.text.isEmpty {
                        Task { await store.summarizeWithAI(record.id) }
                    }
                }
                if saved { dismiss() }
            }.buttonStyle(PrimaryButtonStyle()).disabled(
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Choose another file") {
                imported = nil
                title = ""
                text = ""
            }.frame(maxWidth: .infinity)
        }
    }
}
