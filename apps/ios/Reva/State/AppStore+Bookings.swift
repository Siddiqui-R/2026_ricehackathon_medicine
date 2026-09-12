import Foundation

extension AppStore {
    func save(_ request: BookingRequest) throws {
        try BookingEngine.validate(request)
        try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == request.id }) { data.bookings[i] = request } else { data.bookings.append(request) } }
    }
    func runBooking(_ id: String) async {
        guard let request = booking(id), request.isLive != true, ["draft", "needsUser", "failed"].contains(request.status) else { return }
        guard perform({ try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }) { data.bookings[i].status = "queued" } } }) else { return }
        try? await Task.sleep(for: .seconds(0.7))
        guard perform({ try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }), data.bookings[i].status == "queued" { data.bookings[i].status = "calling" } } }) else { return }
        try? await Task.sleep(for: .seconds(1.3))
        perform { try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }), data.bookings[i].status == "calling" { data.bookings[i].status = request.scenario == "Clinic needs details" ? "needsUser" : request.scenario == "No answer" ? "failed" : "proposed" } } }
    }
    func confirmBooking(_ id: String) throws { try mutate { try BookingEngine.confirm(id: id, snapshot: &$0) } }

}
