// Purpose: Submit reviewed real-call requests and manually refresh their outcome.
// Inputs: An explicitly reviewed BookingRequest or its stable local ID.
// Outputs: Saved provider conversation, status and optional transcript.
// Side effects: May place a real call through the server; never confirms an appointment automatically.

import Foundation

// MARK: - Explicit outbound call
// Save the stable request before sending; an uncertain outcome stays unknown for user review.
extension AppStore {
    func placeLiveCall(_ request: BookingRequest) async {
        guard !isProviderBusy else { return }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            var request = request
            request.isLive = true
            request.status = "starting"
            try save(request)
            let result = try await providerClient().startCall(
                .init(
                    requestID: request.id, clinic: request.clinic, phone: request.phone,
                    reason: request.reason,
                    earliest: request.earliest, latest: request.latest, timeZone: request.timeZone,
                    preferences: request.preferences, patientName: snapshot?.profile.name ?? "", consent: true
                ))
            guard context == providerContext else { return }
            try mutate { data in
                if let i = data.bookings.firstIndex(where: { $0.id == request.id }) {
                    data.bookings[i].providerConversationID = result.conversationID
                    data.bookings[i].status = result.status
                }
            }
            notice =
                "Call request accepted. Check status and review the outcome; Reva has not confirmed an appointment."
        } catch {
            guard context == providerContext else { return }
            perform {
                try mutate { data in
                    if let i = data.bookings.firstIndex(where: { $0.id == request.id }) {
                        data.bookings[i].status = "unknown"
                    }
                }
            }
            errorMessage = error.localizedDescription
        }
    }
    // MARK: - Manual outcome refresh
    // Read the existing request status and transcript without starting another call.
    func refreshLiveCall(_ id: String) async {
        guard !isProviderBusy else { return }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            let result = try await providerClient().callStatus(requestID: id)
            guard context == providerContext else { return }
            try mutate { data in
                if let i = data.bookings.firstIndex(where: { $0.id == id }) {
                    data.bookings[i].providerConversationID = result.conversationID
                    data.bookings[i].status = result.status
                    data.bookings[i].providerTranscript = result.transcript
                }
            }
        } catch {
            guard context == providerContext else { return }
            errorMessage = error.localizedDescription
        }
    }
}
