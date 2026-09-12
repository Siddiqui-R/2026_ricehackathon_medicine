// Purpose: Show booking simulation outcomes or route a live request to its own status screen.
// Inputs: A booking request ID and AppStore.
// Outputs: Readable status, instructions, and explicit simulation confirmation/retry actions.
// Side effects: Can retry the simulation or confirm its proposed time through AppStore.

import SwiftUI

// MARK: - BookingStatusView
/// Show booking simulation outcomes or route a live request to its own status screen.
struct BookingStatusView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    let id: String
    // MARK: - Simulation status vocabulary
    /// Preserve unknown values rather than inventing a confirmation state.
    static func label(_ status: String) -> String {
        [
            "draft": "Ready", "queued": "Queued", "calling": "Simulating call", "proposed": "Time proposed",
            "confirmed": "Demo confirmed", "needsUser": "Needs your input", "failed": "No answer",
        ][status] ?? status
    }
    // MARK: - Rendering and navigation
    var body: some View {
        if let request = store.booking(id), request.isLive == true {
            LiveBookingStatusView(id: id)
        } else if let request = store.booking(id) {
            Page {
                ModeBadge(text: "SIMULATION · NO CALL PLACED")
                RevaCard {
                    Image(
                        systemName: request.status == "confirmed"
                            ? "checkmark.circle.fill"
                            : request.status == "failed" ? "phone.down.circle" : "phone.circle"
                    ).font(.system(size: 54)).foregroundStyle(RevaTheme.accent)
                    Text(Self.label(request.status)).font(.title2.bold())
                    Text(request.clinic).font(.headline)
                    Text(request.phone).font(.subheadline).foregroundStyle(.secondary)
                    if ["queued", "calling"].contains(request.status) {
                        ProgressView("Walking through the demo call…")
                    } else if request.status == "proposed" {
                        Text("A fictional time is available at the beginning of your allowed window.").font(
                            .subheadline
                        ).foregroundStyle(.secondary)
                        DetailLine(
                            symbol: "calendar",
                            text: RevaDate.display(request.earliest, time: true, zone: request.timeZone))
                        Button("Confirm demo appointment") { store.perform { try store.confirmBooking(id) } }
                            .buttonStyle(PrimaryButtonStyle())
                    } else if request.status == "confirmed" {
                        Text("The time is saved to this visit. No appointment was made with a real clinic.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        DetailLine(
                            symbol: "calendar",
                            text: RevaDate.display(request.earliest, time: true, zone: request.timeZone))
                    } else if request.status == "needsUser" {
                        Text(
                            "The demo clinic needs more details, or the simulation was interrupted. You can retry or edit your visit information."
                        ).foregroundStyle(.secondary)
                        Button("Retry simulation") { Task { await store.runBooking(id) } }.buttonStyle(
                            PrimaryButtonStyle())
                    } else if request.status == "failed" {
                        Text("No answer in this simulated attempt. Your appointment has not changed.")
                            .foregroundStyle(.secondary)
                        Button("Retry simulation") { Task { await store.runBooking(id) } }.buttonStyle(
                            PrimaryButtonStyle())
                    }
                }
                RevaCard {
                    Text("Your instructions").font(.headline)
                    Text(request.reason)
                    DetailLine(
                        symbol: "calendar",
                        text: "From " + RevaDate.display(request.earliest, time: true, zone: request.timeZone)
                            + " through "
                            + RevaDate.display(request.latest, time: true, zone: request.timeZone))
                    DetailLine(symbol: "globe.americas", text: request.timeZone)
                    if !request.preferences.isEmpty {
                        Text(request.preferences).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                StatusNotice(
                    title: "Future calling connection",
                    message:
                        "ElevenLabs and telephony credentials will be configured later. This screen demonstrates the review, progress, and outcome flow."
                )
            }.navigationTitle("Booking status").navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Booking unavailable", systemImage: "phone")
        }
    }
}
