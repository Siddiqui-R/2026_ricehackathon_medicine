// Purpose: Present the next visit and shortcuts into records, symptoms, and medical profile.
// Inputs: AppStore plus callbacks selecting the Records and Medical profile tabs.
// Outputs: Summary cards and routes into appointment, record, and symptom workflows.
// Side effects: Dismisses notices and opens editors; child screens own saved mutations.

import SwiftUI

// MARK: - SummaryView
/// Present the next visit and shortcuts into records, symptoms, and medical profile.
struct SummaryView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    let showAllRecords: () -> Void
    let showMedicalProfile: () -> Void
    @State private var addRecord = false
    @State private var addVisit = false
    @State private var logSymptoms = false
    // MARK: - Derived display and validation
    var nextVisit: Visit? { store.visits.first { $0.status == "upcoming" } }
    // MARK: - Rendering and navigation
    var body: some View {
        Page {
            HStack {
                Text("A little preparation.\nA clearer conversation.").font(.subheadline).foregroundStyle(
                    .secondary)
                Spacer()
                ModeBadge()
            }
            if let notice = store.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.footnote)
                    Spacer()
                    Button {
                        store.notice = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.accessibilityLabel("Dismiss notice")
                }.padding(14).background(RevaTheme.soft, in: RoundedRectangle(cornerRadius: 14))
            }
            SectionHeading(title: "Your next visit")
            if let visit = nextVisit {
                RevaCard {
                    HStack {
                        Label(visit.type.uppercased(), systemImage: "calendar").font(.caption.weight(.bold))
                            .tracking(0.7).foregroundStyle(RevaTheme.accent)
                        Spacer()
                        StatusChip(text: "Upcoming")
                    }
                    Text(visit.title).font(.title2.bold())
                    DetailLine(
                        symbol: "clock", text: RevaDate.display(visit.date, time: true, zone: visit.timeZone))
                    DetailLine(symbol: "person.crop.circle", text: visit.provider + " · " + visit.clinic)
                    Divider()
                    Text(visit.concern).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    NavigationLink {
                        VisitDetailView(id: visit.id)
                    } label: {
                        Label("Prepare for this visit", systemImage: "list.bullet.clipboard")
                    }.buttonStyle(PrimaryButtonStyle())
                }
            } else {
                RevaCard {
                    Text("Make room for your next conversation.").font(.headline)
                    Button("Add an appointment") { addVisit = true }.buttonStyle(PrimaryButtonStyle())
                }
            }
            HStack(spacing: 12) {
                Button {
                    addRecord = true
                } label: {
                    quickAction("Add record", symbol: "plus.rectangle.on.folder")
                }
                Button {
                    addVisit = true
                } label: {
                    quickAction("Add visit", symbol: "calendar.badge.plus")
                }
            }.buttonStyle(.plain)
            Button {
                logSymptoms = true
            } label: {
                HStack(spacing: 14) {
                    IconTile(symbol: "square.and.pencil")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log symptoms").font(.headline)
                        Text("Keep track of what you’re feeling.").font(.subheadline).foregroundStyle(
                            .secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(RevaTheme.accent)
                }.padding(18).outlined()
            }.buttonStyle(.plain)
            if store.records.contains(where: \.needsReview) {
                SectionHeading(title: "Needs your review")
                RevaCard {
                    ForEach(store.records.filter(\.needsReview)) { record in
                        NavigationLink {
                            RecordDetailView(id: record.id)
                        } label: {
                            RecordRow(record: record)
                        }.buttonStyle(.plain)
                    }
                    Text("A quick check keeps your medical history accurate.").font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            SectionHeading(title: "Recent records")
            RevaCard {
                if store.records.isEmpty {
                    Text("Add your first document to start building your history.").foregroundStyle(
                        .secondary)
                }
                ForEach(Array(store.records.prefix(3).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { Divider() }
                    NavigationLink {
                        RecordDetailView(id: record.id)
                    } label: {
                        RecordRow(record: record)
                    }.buttonStyle(.plain)
                }
                Divider()
                Button(action: showAllRecords) {
                    HStack {
                        Text("View all records").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(minHeight: 32).contentShape(Rectangle())
                }.accessibilityHint("Opens the Records tab with all records")
            }
        }
        .navigationTitle("Summary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showMedicalProfile) {
                    Text(store.snapshot?.profile.initials ?? "R").font(.caption.bold()).foregroundStyle(
                        RevaTheme.accentText
                    ).frame(width: 36, height: 36).background(RevaTheme.soft, in: Circle())
                }.accessibilityLabel("Medical profile")
            }
        }
        .sheet(isPresented: $addRecord) { NavigationStack { AddRecordView() } }
        .sheet(isPresented: $addVisit) { NavigationStack { VisitEditorView() } }
        .sheet(isPresented: $logSymptoms) { NavigationStack { SymptomEntryEditorView() } }
    }
    // MARK: - Shortcut presentation
    private func quickAction(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(RevaTheme.accent)
            Text(title).font(.headline)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).outlined()
    }
}
