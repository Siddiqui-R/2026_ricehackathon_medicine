import Foundation
import Combine

@MainActor final class AppStore: ObservableObject {
    @Published var snapshot: AppSnapshot?
    @Published var errorMessage: String?
    @Published var startupError: String?
    @Published var notice: String?
    @Published var isSyncing = false
    @Published var serverStatus = "Not connected"
    @Published var serverRevision = 0
    @Published var serverConflictRevision: Int?
    @Published var providerStatus: ProviderStatus?
    @Published var isProviderBusy = false
    @Published var connectionURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8080"
    @Published var connectionToken = "reva-local-demo-token"
    @Published var useConnectedAI = false
    let repository: LocalRepository
    var serverIdentity = ""

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Reva", isDirectory: true)
        repository = LocalRepository(directory: root)
        do {
            if let loaded = try repository.load() {
                snapshot = loaded.snapshot
                if loaded.recovered { notice = "Recovered the last valid checkpoint. Your original files remain available." }
                if snapshot?.bookings.contains(where: { $0.isLive != true && ["queued", "calling"].contains($0.status) }) == true {
                    try mutate { data in for i in data.bookings.indices where data.bookings[i].isLive != true && ["queued", "calling"].contains(data.bookings[i].status) { data.bookings[i].status = "needsUser" } }
                    notice = "An interrupted demo booking needs your attention. Open it to retry."
                }
            } else { try resetDemo() }
        } catch { startupError = error.localizedDescription }
    }
    var records: [MedicalRecord] { (snapshot?.records ?? []).sorted { $0.date > $1.date } }
    var visits: [Visit] { (snapshot?.visits ?? []).sorted { $0.date < $1.date } }
    var bookings: [BookingRequest] { snapshot?.bookings ?? [] }
    var recordings: [VisitRecording] { snapshot?.recordings ?? [] }
    func record(_ id: String) -> MedicalRecord? { records.first { $0.id == id } }
    func visit(_ id: String) -> Visit? { visits.first { $0.id == id } }
    func booking(_ id: String) -> BookingRequest? { bookings.first { $0.id == id } }
    func recording(_ id: String) -> VisitRecording? { recordings.first { $0.id == id } }
    func sourceURL(_ record: MedicalRecord) -> URL? { record.sourceFilename.flatMap(sourceURL) }
    func sourceURL(_ filename: String) -> URL? { repository.attachment(filename) ?? Bundle.main.url(forResource: filename, withExtension: nil) }
    func mutate(_ action: (inout AppSnapshot) throws -> Void) throws {
        guard var next = snapshot else { throw RevaError.invalid("Load or reset the demo first.") }
        try action(&next); try repository.save(next); snapshot = next
    }
    @discardableResult func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); return true } catch { errorMessage = error.localizedDescription; return false }
    }
    func resetDemo() throws {
        guard let url = Bundle.main.url(forResource: "seed", withExtension: "json") else { throw RevaError.invalid("The fictional demo dataset is missing from this build.") }
        let seed = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url)); try seed.validate(); try repository.save(seed)
        snapshot = seed; startupError = nil; notice = "Fictional demo restored."; serverRevision = 0; serverConflictRevision = nil
    }
}
