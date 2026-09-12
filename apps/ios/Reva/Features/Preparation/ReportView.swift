// Purpose: Read a visit brief with traceable sources and export the displayed content.
// Inputs: A visit ID and the saved report/source records from AppStore.
// Outputs: Brief sections, source navigation, editable questions, and a shareable PDF.
// Side effects: Can regenerate the brief and render a temporary PDF for SourcePreview.

import SwiftUI

// MARK: - ReportView
/// Read a visit brief with traceable sources and export the displayed content.
struct ReportView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    let visitID: String
    @State private var edit = false
    @State private var exportDocument: ExportDocument?
    // MARK: - Rendering and navigation
    var body: some View {
        Group {
            if let visit = store.visit(visitID), let report = visit.report {
                Page {
                    ModeBadge(
                        text: report.generationModel == nil
                            ? "LOCAL PRE-VISIT BRIEF" : "AI-ASSISTED · REVIEW SOURCES")
                    Text(visit.title).font(.title.bold())
                    Text(
                        "Prepared \(RevaDate.display(report.createdAt)) · \(report.selectedRecordIDs.count) source records"
                    ).font(.caption).foregroundStyle(.secondary)
                    if ReportEngine.isStale(visit, records: store.records) {
                        StatusNotice(
                            title: "Out of date",
                            message: "Your records or visit details changed. Regenerate before sharing.",
                            symbol: "arrow.clockwise")
                    }
                    ForEach(report.sections) { section in
                        RevaCard {
                            Text(section.title).font(.headline)
                            Text(section.body).font(.subheadline).textSelection(.enabled)
                            ForEach(section.sources) { source in
                                if let notice = source.omissionNotice {
                                    Text(notice).font(.caption).foregroundStyle(.secondary)
                                }
                                NavigationLink {
                                    RecordDetailView(id: source.recordID, sourcePage: source.page)
                                } label: {
                                    Label(
                                        "\(store.record(source.recordID)?.title ?? "Deleted source") · \(source.locationLabel)",
                                        systemImage: "doc.text.magnifyingglass"
                                    ).font(.caption.weight(.medium))
                                }.padding(.top, 4)
                            }
                        }
                    }
                    RevaCard {
                        Text("Questions to bring").font(.headline)
                        ForEach(Array(report.questions.enumerated()), id: \.offset) { index, question in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(
                                    RevaTheme.accentText
                                )
                                .frame(width: 24, height: 24).background(RevaTheme.soft, in: Circle())
                                Text(question).font(.subheadline)
                            }
                        }
                        if report.questions.isEmpty {
                            Text("Add the questions you want to discuss.").foregroundStyle(.secondary)
                        }
                        Button("Edit questions & notes") { edit = true }.font(.subheadline.weight(.semibold))
                    }
                    if !report.notes.isEmpty {
                        RevaCard {
                            Text("Your notes").font(.headline)
                            Text(report.notes)
                        }
                    }
                    StatusNotice(
                        title: "A conversation aid",
                        message:
                            "This brief brings together selected source excerpts. Any AI overview needs review. It does not diagnose or recommend treatment; check the sources with your clinician."
                    )
                    Button(store.isProviderBusy ? "Preparing…" : "Regenerate from current records") {
                        Task { await store.generatePreferredReport(visitID) }
                    }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity).disabled(
                        store.isProviderBusy)
                    Button {
                        exportReport(visit, report)
                    } label: {
                        Label("Share visit brief", systemImage: "square.and.arrow.up")
                    }.buttonStyle(PrimaryButtonStyle()).disabled(
                        ReportEngine.isStale(visit, records: store.records))
                }.sheet(isPresented: $edit) { NavigationStack { ReportEditorView(visit: visit) } }
            } else {
                ContentUnavailableView(
                    "No brief yet", systemImage: "doc.text",
                    description: Text("Generate a brief from the visit screen."))
            }
        }.navigationTitle("Visit brief").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $exportDocument) { document in SourcePreview(url: document.url, title: "Visit brief")
            }
    }
    // MARK: - PDF export
    /// Render the displayed brief with its source labels before presenting the completed file.
    private func exportReport(_ visit: Visit, _ report: VisitReport) {
        store.perform {
            var sections = report.sections.map { section in
                PDFSection(
                    title: section.title,
                    body: section.body
                        + (section.sources.compactMap(\.omissionNotice).isEmpty
                            ? ""
                            : "\n\n" + section.sources.compactMap(\.omissionNotice).joined(separator: "\n"))
                        + (section.sources.isEmpty
                            ? ""
                            : "\n\nSource: "
                                + section.sources.map {
                                    "\(store.record($0.recordID)?.title ?? "Missing") · \($0.locationLabel)"
                                }.joined(separator: "; ")))
            }
            sections.append(
                PDFSection(
                    title: "Questions to bring",
                    body: report.questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(
                        separator: "\n")))
            if !report.notes.isEmpty { sections.append(PDFSection(title: "Your notes", body: report.notes)) }
            let url = try ReportPDFRenderer.render(
                title: "Reva · " + visit.title,
                subtitle: (report.generationModel.map { "AI-assisted (" + $0 + ") · review sources · " }
                    ?? "Local source brief · ")
                    + RevaDate.display(visit.date, time: true, zone: visit.timeZone), sections: sections,
                sources: report.selectedRecordIDs.compactMap { store.record($0) }.map {
                    "\($0.title) · \(RevaDate.display($0.date)) · source version \($0.version)"
                })
            exportDocument = ExportDocument(url: url)
        }
    }
}

// MARK: - ExportDocument
/// Identify a generated PDF sheet by its URL so presentation follows a completed export.
struct ExportDocument: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
