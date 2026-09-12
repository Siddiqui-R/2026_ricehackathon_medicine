import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = false
    @State private var addRecord = false
    @State private var addVisit = false
    var nextVisit: Visit? { store.visits.first { $0.status == "upcoming" } }
    var body: some View {
        Page {
            HStack { Text("A little preparation.\nA clearer conversation.").font(.subheadline).foregroundStyle(.secondary); Spacer(); ModeBadge() }
            if let notice = store.notice {
                HStack(alignment: .top) { Text(notice).font(.footnote); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Dismiss notice") }.padding(14).background(RevaTheme.soft, in: RoundedRectangle(cornerRadius: 14))
            }
            SectionHeading(title: "Your next visit")
            if let visit = nextVisit {
                RevaCard {
                    HStack { Label(visit.type.uppercased(), systemImage: "calendar").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(RevaTheme.accent); Spacer(); Text("UPCOMING").font(.caption2.bold()).foregroundStyle(.secondary) }
                    Text(visit.title).font(.title2.bold())
                    DetailLine(symbol: "clock", text: RevaDate.display(visit.date, time: true, zone: visit.timeZone))
                    DetailLine(symbol: "person.crop.circle", text: visit.provider + " · " + visit.clinic)
                    Divider()
                    Text(visit.concern).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    NavigationLink { VisitDetailView(id: visit.id) } label: { Label("Prepare for this visit", systemImage: "list.bullet.clipboard") }.buttonStyle(PrimaryButtonStyle())
                }
            } else {
                RevaCard { Text("Make room for your next conversation.").font(.headline); Button("Add an appointment") { addVisit = true }.buttonStyle(PrimaryButtonStyle()) }
            }
            HStack(spacing: 12) {
                Button { addRecord = true } label: { quickAction("Add record", symbol: "plus.rectangle.on.folder") }
                Button { addVisit = true } label: { quickAction("Add visit", symbol: "calendar.badge.plus") }
            }.buttonStyle(.plain)
            if store.records.contains(where: \.needsReview) {
                SectionHeading(title: "Needs your review")
                RevaCard {
                    ForEach(store.records.filter(\.needsReview)) { record in NavigationLink { RecordDetailView(id: record.id) } label: { RecordRow(record: record) }.buttonStyle(.plain) }
                    Text("A quick check keeps your medical history accurate.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            SectionHeading(title: "Recent records")
            RevaCard {
                if store.records.isEmpty { Text("Add your first document to start building your history.").foregroundStyle(.secondary) }
                ForEach(Array(store.records.prefix(3).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { Divider() }
                    NavigationLink { RecordDetailView(id: record.id) } label: { RecordRow(record: record) }.buttonStyle(.plain)
                }
            }
            StatusNotice(title: "Your history stays with you", message: "This prototype saves on this device. You decide which records to add and what to bring to your visit.", symbol: "iphone")
        }
        .navigationTitle("Summary")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Text(store.snapshot?.profile.initials ?? "R").font(.caption.bold()).foregroundStyle(RevaTheme.accent).frame(width: 36, height: 36).background(RevaTheme.soft, in: Circle()) }.accessibilityLabel("Profile and settings") } }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $addRecord) { NavigationStack { AddRecordView() } }
        .sheet(isPresented: $addVisit) { NavigationStack { VisitEditorView() } }
    }
    private func quickAction(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) { Image(systemName: symbol).font(.title2).foregroundStyle(RevaTheme.accent); Text(title).font(.headline) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(RevaTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
