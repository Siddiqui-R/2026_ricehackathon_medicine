// Purpose: Browse and search saved documents and symptom entries.
// Inputs: AppStore records plus the selected filter and search text.
// Outputs: Record rows and routes to detail, import, and symptom entry screens.
// Side effects: Changes local filter/sheet state; child editors own persistence.

import SwiftUI

// MARK: - RecordsView
/// Browse and search saved documents and symptom entries.
struct RecordsView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var filter = "All"
    @State private var adding = false
    @State private var loggingSymptoms = false
    let filters = [
        "All", "Symptoms", "Needs review", "Notes", "Labs", "Imaging", "Procedure", "Scan", "Recording",
    ]
    // MARK: - Derived display and validation
    var filtered: [MedicalRecord] {
        store.records.filter { record in
            (filter == "All"
                || (filter == "Symptoms"
                    ? record.symptomEntry != nil
                    : filter == "Needs review" ? record.needsReview : record.kind == filter))
                && (query.isEmpty
                    || ([
                        record.title, record.provider, record.tags.joined(separator: " "), record.text,
                        record.summary, record.date, RevaDate.display(record.date),
                    ].joined(separator: " ")).localizedCaseInsensitiveContains(query))
        }
    }
    // MARK: - Rendering and navigation
    var body: some View {
        Page {
            Text("Your history, all in one place.").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { item in
                        Button {
                            filter = item
                        } label: {
                            Text(item).font(.subheadline.weight(.medium)).padding(.horizontal, 15).padding(
                                .vertical, 10
                            ).background(filter == item ? RevaTheme.accent : RevaTheme.surface, in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        filter == item ? Color.clear : RevaTheme.hairline, lineWidth: 1)
                                )
                                .foregroundStyle(filter == item ? RevaTheme.buttonText : .primary)
                        }.accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
            }
            Text("\(filtered.count) \(filtered.count == 1 ? "record" : "records")").font(.caption)
                .foregroundStyle(.secondary)
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query.isEmpty ? filter : query)
                Button(filter == "Symptoms" ? "Log symptoms" : "Add a record") {
                    if filter == "Symptoms" { loggingSymptoms = true } else { adding = true }
                }.buttonStyle(PrimaryButtonStyle())
            } else {
                RevaCard {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider() }
                        NavigationLink {
                            RecordDetailView(id: record.id)
                        } label: {
                            RecordRow(record: record)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.navigationTitle("Records").searchable(text: $query, prompt: "Search records, dates, or details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add a document", systemImage: "doc.badge.plus") { adding = true }
                        Button("Log symptoms", systemImage: "square.and.pencil") { loggingSymptoms = true }
                    } label: {
                        Image(systemName: "plus")
                    }.accessibilityLabel("Add record or symptom entry")
                }
            }
            .sheet(isPresented: $adding) { NavigationStack { AddRecordView() } }
            .sheet(isPresented: $loggingSymptoms) { NavigationStack { SymptomEntryEditorView() } }
    }
}
