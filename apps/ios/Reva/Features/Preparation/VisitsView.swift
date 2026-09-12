// Purpose: Browse upcoming and past appointments.
// Inputs: AppStore visits and the selected appointment status.
// Outputs: Visit rows and routes to appointment detail or creation.
// Side effects: Changes local selection and sheet state; the visit editor saves changes.

import SwiftUI

// MARK: - VisitsView
/// Browse upcoming and past appointments.
struct VisitsView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @State private var adding = false
    @State private var selection = "Upcoming"
    // MARK: - Derived display and validation
    var filtered: [Visit] {
        store.visits.filter { $0.status == (selection == "Upcoming" ? "upcoming" : "completed") }
    }
    // MARK: - Rendering and navigation
    var body: some View {
        Page {
            Text("Before, during, and after your visit.").font(.subheadline).foregroundStyle(.secondary)
            Picker("Visits", selection: $selection) {
                Text("Upcoming").tag("Upcoming")
                Text("Past").tag("Past")
            }.pickerStyle(.segmented)
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No \(selection.lowercased()) visits", systemImage: "calendar",
                    description: Text("Add an appointment to prepare your history and questions."))
                Button("Add a visit") { adding = true }.buttonStyle(PrimaryButtonStyle())
            }
            ForEach(filtered) { visit in
                NavigationLink {
                    VisitDetailView(id: visit.id)
                } label: {
                    RevaCard {
                        VisitRow(visit: visit)
                        Divider()
                        Text(visit.concern).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        Label(
                            visit.report == nil
                                ? "Ready to prepare"
                                : ReportEngine.isStale(visit, records: store.records)
                                    ? "Brief needs an update" : "Brief ready",
                            systemImage: visit.report == nil ? "list.bullet.clipboard" : "doc.text"
                        ).font(.caption.weight(.medium)).foregroundStyle(RevaTheme.accent)
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Visits").toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }.accessibilityLabel("Add visit")
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { VisitEditorView() } }
    }
}
