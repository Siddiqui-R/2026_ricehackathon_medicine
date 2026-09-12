// Purpose: Review an outbound clinic call without treating call completion as a booking.
// Inputs: A booking request ID and its provider state from AppStore.
// Outputs: Provider status, transcript, and a route to update the visit after confirmation.
// Side effects: Refreshes status only on user action; the linked visit editor owns appointment edits.

import SwiftUI

// MARK: - LiveBookingStatusView
/// Review an outbound clinic call without treating call completion as a booking.
struct LiveBookingStatusView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    let id: String
    // MARK: - Rendering and navigation
    var body: some View {
        if let request = store.booking(id) {
            Page {
                ModeBadge(text: "CONNECTED CALL · REVIEW OUTCOME")
                RevaCard {
                    Text(request.clinic).font(.title2.bold())
                    Text(request.phone).foregroundStyle(.secondary)
                    LabeledContent("Provider status", value: request.status)
                    if let conversation = request.providerConversationID {
                        Text("Conversation: " + conversation).font(.caption).textSelection(.enabled)
                    }
                    Button(store.isProviderBusy ? "Checking…" : "Check call status") {
                        Task { await store.refreshLiveCall(id) }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(store.isProviderBusy)
                }
                StatusNotice(
                    title: "Confirm the result",
                    message:
                        "A completed call is not automatically a booked appointment. Check what the clinic said and update your visit date only when confirmed. Uncertain or interrupted requests are not automatically redialed."
                )
                if let transcript = request.providerTranscript, !transcript.isEmpty {
                    RevaCard {
                        Text("Call transcript").font(.headline)
                        Text(transcript).textSelection(.enabled)
                    }
                }
                if let visit = store.visit(request.visitID) {
                    NavigationLink {
                        VisitEditorView(existing: visit)
                    } label: {
                        Label("Update visit after confirmation", systemImage: "calendar")
                    }.buttonStyle(.bordered)
                }
            }.navigationTitle("Call status").navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Call unavailable", systemImage: "phone")
        }
    }
}
