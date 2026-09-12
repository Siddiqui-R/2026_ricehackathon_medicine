// Purpose: Validate booking details and confirm a simulated proposal once.
// Inputs: A booking request and an inout application snapshot.
// Outputs: Validation errors or an updated existing visit and booking.
// Side effects: Mutates the supplied snapshot only; never dials a clinic.

import Foundation

// MARK: - Simulation domain rules
// Validate request windows and update the existing visit only after a proposed outcome.
enum BookingEngine {
    static func validate(_ request: BookingRequest) throws {
        guard !request.clinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            request.phone.filter(\.isNumber).count >= 10,
            !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw RevaError.invalid("Enter a clinic, a complete phone number, and the visit reason.") }
        guard RevaDate.parse(request.earliest) <= RevaDate.parse(request.latest),
            TimeZone(identifier: request.timeZone) != nil
        else { throw RevaError.invalid("Check the date range and time zone.") }
    }
    // MARK: - Idempotent confirmation
    // Return early after confirmation; missing or non-proposed requests are rejected.
    static func confirm(id: String, snapshot: inout AppSnapshot) throws {
        guard let index = snapshot.bookings.firstIndex(where: { $0.id == id }) else {
            throw RevaError.invalid("Booking not found.")
        }
        if snapshot.bookings[index].confirmedVisitID != nil { return }
        guard snapshot.bookings[index].status == "proposed",
            let visitIndex = snapshot.visits.firstIndex(where: { $0.id == snapshot.bookings[index].visitID })
        else { throw RevaError.invalid("This booking is not ready to confirm.") }
        let request = snapshot.bookings[index]
        snapshot.visits[visitIndex].date = request.earliest
        snapshot.visits[visitIndex].clinic = request.clinic
        snapshot.visits[visitIndex].timeZone = request.timeZone
        snapshot.bookings[index].status = "confirmed"
        snapshot.bookings[index].confirmedVisitID = snapshot.visits[visitIndex].id
    }
}
