import SwiftUI

/// Live calling has its own review surface; simulation remains available independently.
struct LiveBookingEditorView: View {
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
    private var valid: Bool {
        phone.hasPrefix("+") && (10...15).contains(phone.dropFirst().count) && phone.dropFirst().allSatisfy(\.isNumber)
            && !clinic.trimmingCharacters(in: .whitespaces).isEmpty && !reason.trimmingCharacters(in: .whitespaces).isEmpty && consent && earliest <= latest
    }
    var body: some View {
        RevaForm {
            Section {
                Label("Real clinic call", systemImage: "phone.arrow.up.right").font(.headline)
                Text("The connected ElevenLabs agent will call this number and receive your name, visit reason, and scheduling preferences. Review every field before placing a call.").foregroundStyle(.secondary)
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
            }.environment(\.timeZone, TimeZone(identifier: visit.timeZone) ?? .current)
            Section {
                Toggle("I authorize this call and sharing these details", isOn: $consent)
                Button("Review & place real call") { confirm = true }.disabled(!valid || submitted || store.isProviderBusy)
            } footer: {
                Text("Call completion does not establish an appointment. Review the transcript and clinic outcome, then edit your visit if a time is confirmed. An uncertain call is never automatically redialed.")
            }
        }.navigationTitle("Call clinic").navigationBarTitleDisplayMode(.inline)
            .onAppear { clinic = visit.clinic; reason = visit.concern; earliest = RevaDate.parse(visit.date); latest = earliest.addingTimeInterval(86400 * 7) }
            .confirmationDialog("Place a real call to \(clinic) at \(phone)? Your name, reason, and allowed date window will be shared with the connected calling service.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Place real call") {
                    var request = BookingRequest(visitID: visit.id, clinic: clinic, phone: phone, reason: reason, earliest: RevaDate.iso(earliest), latest: RevaDate.iso(latest), timeZone: visit.timeZone, preferences: preferences)
                    request.isLive = true
                    if store.perform({ try store.save(request) }) { submitted = true; requestID = request.id; Task { await store.placeLiveCall(request) } }
                }
            }
            .navigationDestination(item: $requestID) { LiveBookingStatusView(id: $0) }
    }
}

struct LiveBookingStatusView: View {
    @EnvironmentObject private var store: AppStore
    let id: String
    var body: some View {
        if let request = store.booking(id) {
            Page {
                ModeBadge(text: "CONNECTED CALL · REVIEW OUTCOME")
                RevaCard {
                    Text(request.clinic).font(.title2.bold())
                    Text(request.phone).foregroundStyle(.secondary)
                    LabeledContent("Provider status", value: request.status)
                    if let conversation = request.providerConversationID { Text("Conversation: " + conversation).font(.caption).textSelection(.enabled) }
                    Button(store.isProviderBusy ? "Checking…" : "Check call status") { Task { await store.refreshLiveCall(id) } }.buttonStyle(PrimaryButtonStyle()).disabled(store.isProviderBusy)
                }
                StatusNotice(title: "Confirm the result", message: "A completed call is not automatically a booked appointment. Check what the clinic said and update your visit date only when confirmed. Uncertain or interrupted requests are not automatically redialed.")
                if let transcript = request.providerTranscript, !transcript.isEmpty {
                    RevaCard { Text("Call transcript").font(.headline); Text(transcript).textSelection(.enabled) }
                }
                if let visit = store.visit(request.visitID) {
                    NavigationLink { VisitEditorView(existing: visit) } label: { Label("Update visit after confirmation", systemImage: "calendar") }.buttonStyle(.bordered)
                }
            }.navigationTitle("Call status").navigationBarTitleDisplayMode(.inline)
        } else { ContentUnavailableView("Call unavailable", systemImage: "phone") }
    }
}
