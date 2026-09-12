// Purpose: Own observable app state and the single snapshot mutation boundary.
// Inputs: Saved snapshots, bundled fictional fixtures and user mutations.
// Outputs: Published snapshot/query results and user-visible notices or errors.
// Side effects: Reads/writes local state; recovers/reset fixtures and stores session settings.

import Combine

// MARK: - Observable state owner
// Keep view state on the main actor; mutate publishes only after repository save succeeds.
import Foundation

@MainActor final class AppStore: ObservableObject {
    @Published var snapshot: AppSnapshot? {
        didSet { snapshotGeneration = UUID() }
    }
    @Published var errorMessage: String?
    @Published var startupError: String?
    @Published var notice: String?
    @Published var isSyncing = false
    @Published var serverStatus = "Not connected"
    @Published var serverRevision = 0
    @Published var serverConflictRevision: Int?
    @Published var providerStatus: ProviderStatus?
    @Published var isProviderBusy = false
    @Published var connectionURL =
        UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8080"
    {
        didSet { if connectionURL != oldValue { connectionDidChange() } }
    }
    @Published var connectionToken = "reva-local-demo-token" {
        didSet { if connectionToken != oldValue { connectionDidChange() } }
    }
    @Published var useConnectedAI = false
    let repository: LocalRepository
    var serverIdentity = ""
    private(set) var snapshotGeneration = UUID()
    private(set) var connectionGeneration = UUID()
    var providerDiscoveryID = UUID()

    // MARK: - Invalidate in-flight connection results
    // A generation also catches switching away and back while an old request is suspended.
    private func connectionDidChange() {
        connectionGeneration = UUID()
        serverIdentity = ""
        serverRevision = 0
        serverConflictRevision = nil
        serverStatus = "Not connected"
        providerStatus = nil
        useConnectedAI = false
    }

    // MARK: - Startup and recovery
    // Restore a valid snapshot, repair known demo labels/interrupted simulations, or load bundled fixtures.
    init(repository: LocalRepository? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reva", isDirectory: true)
        self.repository = repository ?? LocalRepository(directory: root)
        do {
            if let loaded = try self.repository.load() {
                snapshot = loaded.snapshot
                if loaded.recovered {
                    notice = "Recovered the last valid checkpoint. Your original files remain available."
                }
                // Rename only the untouched demo label. Preserve scanned wording, originals, and user edits.
                if var sample = snapshot?.records.first(where: {
                    $0.id == "demo-record-symptom-diary"
                        && $0.title == "Nausea and palpitation diary - date needs review"
                }) {
                    sample.title = "Scanned symptom note - date needs review"
                    try save(sample)
                }
                if snapshot?.bookings.contains(where: {
                    $0.isLive != true && ["queued", "calling"].contains($0.status)
                }) == true {
                    try mutate { data in
                        for i in data.bookings.indices
                        where data.bookings[i].isLive != true
                            && ["queued", "calling"].contains(data.bookings[i].status)
                        { data.bookings[i].status = "needsUser" }
                    }
                    notice = "An interrupted demo booking needs your attention. Open it to retry."
                }
            } else {
                try resetDemo()
            }
        } catch { startupError = error.localizedDescription }
    }
    // MARK: - Read models and source lookup
    // Expose sorted projections without granting another object ownership of persistence.
    var records: [MedicalRecord] {
        (snapshot?.records ?? []).sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            let left = RevaDate.parse($0.symptomEntry?.observedAt ?? $0.uploadedAt)
            let right = RevaDate.parse($1.symptomEntry?.observedAt ?? $1.uploadedAt)
            return left == right ? $0.id < $1.id : left > right
        }
    }
    var visits: [Visit] { (snapshot?.visits ?? []).sorted { $0.date < $1.date } }
    var bookings: [BookingRequest] { snapshot?.bookings ?? [] }
    var recordings: [VisitRecording] { snapshot?.recordings ?? [] }
    func record(_ id: String) -> MedicalRecord? { snapshot?.records.first { $0.id == id } }
    func visit(_ id: String) -> Visit? { snapshot?.visits.first { $0.id == id } }
    func booking(_ id: String) -> BookingRequest? { bookings.first { $0.id == id } }
    func recording(_ id: String) -> VisitRecording? { recordings.first { $0.id == id } }
    func sourceURL(_ record: MedicalRecord) -> URL? { record.sourceFilename.flatMap(sourceURL) }
    func sourceURL(_ filename: String) -> URL? {
        repository.attachment(filename) ?? Bundle.main.url(forResource: filename, withExtension: nil)
    }
    // MARK: - Atomic state mutation
    // Mutate a value copy, validate/save it, then publish; failed saves leave the active value intact.
    func mutate(_ action: (inout AppSnapshot) throws -> Void) throws {
        guard var next = snapshot else { throw RevaError.invalid("Load or reset the demo first.") }
        try action(&next)
        try repository.save(next)
        snapshot = next
    }
    // MARK: - UI error boundary
    // Convert thrown operations to one user-visible error and a success flag for dismissal.
    @discardableResult func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    // MARK: - Explicit demo restoration
    // Replace active state with validated bundled fictional data; originals remain on disk.
    func resetDemo() throws {
        guard let url = Bundle.main.url(forResource: "seed", withExtension: "json") else {
            throw RevaError.invalid("The fictional demo dataset is missing from this build.")
        }
        let seed = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url))
        try seed.validate()
        try repository.save(seed)
        snapshot = seed
        startupError = nil
        notice = "Fictional demo restored."
        serverRevision = 0
        serverConflictRevision = nil
    }
}
