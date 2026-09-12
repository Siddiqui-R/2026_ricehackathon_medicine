import SwiftUI

struct BookingEditorView: View {
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
    var body: some View {
        Form {
            Section { Label("Booking simulation", systemImage: "phone.badge.waveform").font(.headline); Text("Review the information a future calling assistant would use. This demo never dials or contacts a clinic.").font(.subheadline).foregroundStyle(.secondary) }
            Section("Clinic & purpose") { TextField("Clinic name", text: $clinic); TextField("Phone number", text: $phone).keyboardType(.phonePad); TextField("Visit reason", text: $reason, axis: .vertical).lineLimit(2...5) }
            Section("Allowed appointment window") { DatePicker("Earliest / demo proposal", selection: $earliest); DatePicker("Latest", selection: $latest, in: earliest...); Text(visit.timeZone).font(.caption).foregroundStyle(.secondary); TextField("Preferences and constraints", text: $preferences, axis: .vertical).lineLimit(2...4) }.environment(\.timeZone, TimeZone(identifier: visit.timeZone) ?? .current)
            Section { Picker("Demo outcome", selection: $scenario) { ForEach(["Appointment available", "Clinic needs details", "No answer"], id: \.self) { Text($0) } } } footer: { Text("Choose an outcome to demonstrate both successful and interrupted bookings.") }
            Section { Toggle("I reviewed the clinic and date constraints", isOn: $reviewed); Button("Start booking simulation") { start() }.disabled(!reviewed || clinic.isEmpty || reason.isEmpty || phone.filter(\.isNumber).count < 10 || created) }
        }.navigationTitle("Request booking").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { clinic = visit.clinic; reason = visit.concern; earliest = RevaDate.parse(visit.date); latest = earliest.addingTimeInterval(86400 * 7) }
            .navigationDestination(item: $requestID) { BookingStatusView(id: $0) }
    }
    private func start() {
        let request = BookingRequest(visitID: visit.id, clinic: clinic, phone: phone, reason: reason, earliest: RevaDate.iso(earliest), latest: RevaDate.iso(latest), timeZone: visit.timeZone, preferences: preferences, scenario: scenario)
        if store.perform({ try store.save(request) }) { created = true; requestID = request.id; Task { await store.runBooking(request.id) } }
    }
}
struct BookingStatusView: View {
    @EnvironmentObject private var store: AppStore
    let id: String
    static func label(_ status: String) -> String {
        ["draft": "Ready", "queued": "Queued", "calling": "Simulating call", "proposed": "Time proposed", "confirmed": "Demo confirmed", "needsUser": "Needs your input", "failed": "No answer"][status] ?? status
    }
    var body: some View {
        if let request = store.booking(id) {
            Page {
                ModeBadge(text: "SIMULATION · NO CALL PLACED")
                RevaCard {
                    Image(systemName: request.status == "confirmed" ? "checkmark.circle.fill" : request.status == "failed" ? "phone.down.circle" : "phone.circle").font(.system(size: 54)).foregroundStyle(RevaTheme.accent)
                    Text(Self.label(request.status)).font(.title2.bold())
                    Text(request.clinic).font(.headline)
                    Text(request.phone).font(.subheadline).foregroundStyle(.secondary)
                    if ["queued", "calling"].contains(request.status) { ProgressView("Walking through the demo call…") }
                    else if request.status == "proposed" {
                        Text("A fictional time is available at the beginning of your allowed window.").font(.subheadline).foregroundStyle(.secondary)
                        DetailLine(symbol: "calendar", text: RevaDate.display(request.earliest, time: true, zone: request.timeZone))
                        Button("Confirm demo appointment") { store.perform { try store.confirmBooking(id) } }.buttonStyle(PrimaryButtonStyle())
                    } else if request.status == "confirmed" {
                        Text("The time is saved to this visit. No appointment was made with a real clinic.").font(.subheadline).foregroundStyle(.secondary)
                        DetailLine(symbol: "calendar", text: RevaDate.display(request.earliest, time: true, zone: request.timeZone))
                    } else if request.status == "needsUser" {
                        Text("The demo clinic needs more details, or the simulation was interrupted. You can retry or edit your visit information.").foregroundStyle(.secondary)
                        Button("Retry simulation") { Task { await store.runBooking(id) } }.buttonStyle(PrimaryButtonStyle())
                    } else if request.status == "failed" {
                        Text("No answer in this simulated attempt. Your appointment has not changed.").foregroundStyle(.secondary)
                        Button("Retry simulation") { Task { await store.runBooking(id) } }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                RevaCard {
                    Text("Your instructions").font(.headline)
                    Text(request.reason)
                    DetailLine(symbol: "calendar", text: "From " + RevaDate.display(request.earliest, time: true, zone: request.timeZone) + " through " + RevaDate.display(request.latest, time: true, zone: request.timeZone))
                    DetailLine(symbol: "globe.americas", text: request.timeZone)
                    if !request.preferences.isEmpty { Text(request.preferences).font(.subheadline).foregroundStyle(.secondary) }
                }
                StatusNotice(title: "Future calling connection", message: "ElevenLabs and telephony credentials will be configured later. This screen demonstrates the review, progress, and outcome flow.")
            }.navigationTitle("Booking status").navigationBarTitleDisplayMode(.inline)
        } else { ContentUnavailableView("Booking unavailable", systemImage: "phone") }
    }
}
