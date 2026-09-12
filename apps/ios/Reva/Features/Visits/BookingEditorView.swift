// Purpose: Review the information used by the local appointment-booking simulation.
// Inputs: A Visit and the user-selected fictional outcome and date constraints.
// Outputs: A saved simulation request and its status screen.
// Side effects: Persists one request and starts the local simulation; this screen never places a call.

import SwiftUI

// MARK: - BookingEditorView
/// Review the information used by the local appointment-booking simulation.
struct BookingEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    @State private var clinic = ""
    @State private var phone = "713-555-0100"
    @State private var reason = ""
    @State private var earliest = Date().addingTimeInterval(86400 * 3)
    @State private var latest = Date().addingTimeInterval(86400 * 7)
    @State private var preferences = "Morning preferred"
    @State private var scenario = "Appointment available"
    @State private var reviewed = false
    @State private var requestID: String?
    @State private var created = false
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section {
                Label("Booking simulation", systemImage: "phone.badge.waveform").font(.headline)
                Text(
                    "Review the information a future calling assistant would use. This demo never dials or contacts a clinic."
                ).font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Clinic & purpose") {
                TextField("Clinic name", text: $clinic)
                TextField("Phone number", text: $phone).keyboardType(.phonePad)
                TextField("Visit reason", text: $reason, axis: .vertical).lineLimit(2...5)
            }
            Section("Allowed appointment window") {
                DatePicker("Earliest / demo proposal", selection: $earliest)
                DatePicker("Latest", selection: $latest, in: earliest...)
                Text(visit.timeZone).font(.caption).foregroundStyle(.secondary)
                TextField("Preferences and constraints", text: $preferences, axis: .vertical).lineLimit(2...4)
            }.environment(\.timeZone, TimeZone(identifier: visit.timeZone) ?? .current)
            Section {
                Picker("Demo outcome", selection: $scenario) {
                    ForEach(["Appointment available", "Clinic needs details", "No answer"], id: \.self) {
                        Text($0)
                    }
                }
            } footer: {
                Text("Choose an outcome to demonstrate both successful and interrupted bookings.")
            }
            Section {
                Toggle("I reviewed the clinic and date constraints", isOn: $reviewed)
                Button("Start booking simulation") { start() }.disabled(
                    !reviewed || clinic.isEmpty || reason.isEmpty || phone.filter(\.isNumber).count < 10
                        || created)
            }
        }.navigationTitle("Request booking").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                clinic = visit.clinic
                reason = visit.concern
                earliest = RevaDate.parse(visit.date)
                latest = earliest.addingTimeInterval(86400 * 7)
            }
            .navigationDestination(item: $requestID) { BookingStatusView(id: $0) }
    }
    // MARK: - Start one simulation
    /// Save the request before running the local outcome and opening its status screen.
    private func start() {
        let request = BookingRequest(
            visitID: visit.id, clinic: clinic, phone: phone, reason: reason, earliest: RevaDate.iso(earliest),
            latest: RevaDate.iso(latest), timeZone: visit.timeZone, preferences: preferences,
            scenario: scenario)
        if store.perform({ try store.save(request) }) {
            created = true
            requestID = request.id
            Task { await store.runBooking(request.id) }
        }
    }
}
