// Purpose: Review and authorize a configured outbound clinic call.
// Inputs: A Visit, clinic number, scheduling constraints, consent, and AppStore.
// Outputs: A saved live BookingRequest and a route to its provider status.
// Side effects: After explicit confirmation, saves the request and asks AppStore to place the real call.

import SwiftUI

// MARK: - LiveBookingEditorView
/// Review and authorize a configured outbound clinic call.
/// Live calling has its own review surface; simulation remains available independently.
struct LiveBookingEditorView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    let visit: Visit
    @State private var phone = ""
    @State private var clinic = ""
    @State private var reason = ""
    @State private var preferences = ""
    @State private var earliest = Date()
    @State private var latest = Date()
    @State private var consent = false
    @State private var confirm = false
    @State private var requestID: String?
    @State private var submitted = false
    // MARK: - Derived display and validation
    private var valid: Bool {
        phone.hasPrefix("+") && (10...15).contains(phone.dropFirst().count)
            && phone.dropFirst().allSatisfy(\.isNumber)
            && !clinic.trimmingCharacters(in: .whitespaces).isEmpty
            && !reason.trimmingCharacters(in: .whitespaces).isEmpty && consent && earliest <= latest
    }
    // MARK: - Rendering and navigation
    var body: some View {
        RevaForm {
            Section {
                Label("Real clinic call", systemImage: "phone.arrow.up.right").font(.headline)
                Text(
                    "The connected ElevenLabs agent will call this number and receive your name, visit reason, and scheduling preferences. Review every field before placing a call."
                ).foregroundStyle(.secondary)
            }
            Section("Call details") {
                TextField("Clinic", text: $clinic)
                TextField("Phone in +countrycode format", text: $phone).keyboardType(.phonePad)
                TextField("Reason shared with the clinic", text: $reason, axis: .vertical).lineLimit(2...5)
                LabeledContent("Patient name", value: store.snapshot?.profile.name ?? "")
            }
            Section("Allowed window") {
                DatePicker("Earliest", selection: $earliest)
                DatePicker("Latest", selection: $latest, in: earliest...)
                Text(visit.timeZone).font(.caption)
                TextField("Scheduling preferences", text: $preferences, axis: .vertical)
            }.environment(\.timeZone, TimeZone(identifier: visit.timeZone) ?? RevaDate.defaultTimeZone)
            Section {
                Toggle("I authorize this call and sharing these details", isOn: $consent)
                Button("Review & place real call") { confirm = true }.disabled(
                    !valid || submitted || store.isProviderBusy)
            } footer: {
                Text(
                    "Call completion does not establish an appointment. Review the transcript and clinic outcome, then edit your visit if a time is confirmed. An uncertain call is never automatically redialed."
                )
            }
        }.navigationTitle("Call clinic").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                clinic = visit.clinic
                reason = visit.concern
                earliest = RevaDate.parse(visit.date)
                latest = earliest.addingTimeInterval(86400 * 7)
            }
            .confirmationDialog(
                "Place a real call to \(clinic) at \(phone)? Your name, reason, and allowed date window will be shared with the connected calling service.",
                isPresented: $confirm, titleVisibility: .visible
            ) {
                Button("Place real call") {
                    var request = BookingRequest(
                        visitID: visit.id, clinic: clinic, phone: phone, reason: reason,
                        earliest: RevaDate.iso(earliest), latest: RevaDate.iso(latest),
                        timeZone: visit.timeZone, preferences: preferences)
                    request.isLive = true
                    if store.perform({ try store.save(request) }) {
                        submitted = true
                        requestID = request.id
                        Task { await store.placeLiveCall(request) }
                    }
                }
            }
            .navigationDestination(item: $requestID) { LiveBookingStatusView(id: $0) }
    }
}
