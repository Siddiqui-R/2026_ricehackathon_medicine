// Purpose: Reproduce late provider publication against the frozen production AppStore.
// Inputs: Synthetic demo fixture and unchanged production Swift sources.
// Outputs: Named observations; preconditions fail if the reported behavior cannot reproduce.
// Side effects: Temporary snapshot directory only. Provider calls are deterministic test doubles.
import Foundation

// MARK: - Provider transport double
// Suspend at the network boundary; the callback changes the owner before the old result returns.
@MainActor struct ProviderClient {
    static var duringRequest: (() async throws -> Void)?
    init(url: String, token: String) throws {}
    func status() async throws -> ProviderStatus {
        fatalError("Capability discovery is not exercised")
    }
    func summarize(_ record: MedicalRecord) async throws -> AISummary {
        try await Self.duringRequest?()
        return AISummary(summary: "Synthetic owner A provider summary", model: "audit-double")
    }
    func prepare(_ visit: Visit, records: [MedicalRecord]) async throws -> AIPreparation {
        try await Self.duringRequest?()
        return AIPreparation(overview: "Synthetic owner A overview", questions: [], selectedRecordIDs: [], model: "audit-double")
    }
    func startCall(_ input: LiveCallInput) async throws -> LiveCallResult {
        try await Self.duringRequest?()
        return LiveCallResult(conversationID: "synthetic-owner-a", status: "completed", provider: "audit-double", transcript: "Synthetic owner A transcript")
    }
    func callStatus(requestID: String) async throws -> LiveCallResult {
        try await Self.duringRequest?()
        return LiveCallResult(conversationID: "synthetic-owner-a", status: "completed", provider: "audit-double", transcript: "Synthetic owner A transcript")
    }
}

// MARK: - Deterministic production state checks
@main struct ProviderContextRepro {
    @MainActor static func main() async throws {
        let fixture = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let root = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("reva-audit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(directory: root)
        try repository.save(fixture)
        let store = AppStore(repository: repository)
        precondition(store.startupError == nil)
        let recordID = fixture.records[0].id
        store.connectionToken = "synthetic-owner-a"
        let generationA = store.connectionGeneration
        ProviderClient.duringRequest = {
            await Task.yield()
            store.connectionToken = "synthetic-owner-b"
        }
        await store.summarizeWithAI(recordID)
        precondition(store.connectionGeneration != generationA)
        precondition(store.record(recordID)?.summary == "Synthetic owner A provider summary")
        print("REPRODUCED: summary request begun on owner A publishes after token switches to owner B")

        // A pulled snapshot may legitimately share stable IDs, e.g. both owners seeded from the demo.
        let request = BookingRequest(id: "shared-synthetic-request", visitID: fixture.visits[0].id, clinic: "Synthetic clinic", phone: "+15555550123", reason: "Synthetic review", earliest: "2026-09-15T09:00:00Z", latest: "2026-09-16T09:00:00Z", timeZone: "America/Chicago", preferences: "", status: "starting", isLive: true)
        try store.save(request)
        store.connectionToken = "synthetic-owner-a"
        ProviderClient.duringRequest = {
            await Task.yield()
            store.connectionToken = "synthetic-owner-b"
            var ownerB = fixture
            ownerB.profile.name = "Synthetic owner B"
            ownerB.bookings = [request]
            try store.mutate { $0 = ownerB }
        }
        await store.refreshLiveCall(request.id)
        precondition(store.snapshot?.profile.name == "Synthetic owner B")
        precondition(store.booking(request.id)?.providerTranscript == "Synthetic owner A transcript")
        print("REPRODUCED: delayed owner A call transcript is persisted in owner B snapshot with matching request ID")
        print("LIMIT: real provider, HTTP transport, login UI and UI timing were not exercised; production state mutation was")

        // Check browser goldens using the actual unchanged Swift signature implementation.
        let expectedSignatures = [
            "b2437a79a5c1570e95aa2b950dcfab9c4902cae100e345b3a916e46416b67731",
            "6b7fbb5244c4de15d80c6d54c91105501dc274a1e7598efe8d1c3dc9ccc9a163",
            "5718d660263731137b3f7e55d3c7e3528c7b3d8848d9be12845b7bed25cda619"
        ]
        let actualSignatures = fixture.visits.map { ReportEngine.signature(visit: $0, records: fixture.records) }
        precondition(actualSignatures == expectedSignatures)
        print("PASS: all three browser signature goldens match the frozen production Swift ReportEngine")

        // Mixed ISO offsets represent valid instants but sort differently as unparsed strings.
        var earlier = fixture.visits[0]
        earlier.id = "synthetic-earlier"
        earlier.date = "2026-10-01T10:00:00+02:00"
        var later = fixture.visits[0]
        later.id = "synthetic-later"
        later.date = "2026-10-01T08:45:00Z"
        try store.mutate { $0.visits = [earlier, later]; $0.bookings = []; $0.recordings = [] }
        precondition(RevaDate.parse(earlier.date) < RevaDate.parse(later.date))
        precondition(store.visits.first?.id == later.id)
        print("REPRODUCED: native visit projection puts 08:45Z before 10:00+02:00 (08:00Z)")

        // Force only a repair write to fail; a previously validated state.json remains readable.
        var needsRepair = fixture
        var interrupted = request
        interrupted.isLive = false
        interrupted.status = "queued"
        needsRepair.bookings = [interrupted]
        try repository.save(needsRepair)
        try FileManager.default.removeItem(at: repository.attachmentDirectory)
        try Data("synthetic blocking file".utf8).write(to: repository.attachmentDirectory)
        let repairedStore = AppStore(repository: repository)
        precondition(repairedStore.snapshot != nil && repairedStore.startupError != nil)
        precondition(repairedStore.snapshot?.profile == needsRepair.profile)
        print("REPRODUCED: failed startup repair leaves valid loaded snapshot but sets startupError, selecting RootView recovery screen")
        print("LIMIT: repair failure simulated with a blocking filesystem entry; recovery UI presentation inspected from source only")

        // Excerpt boundaries must disclose omission and avoid silently trimming ordinary source headers.
        let doseSource = String(repeating: "x", count: 1791) + " dose: 100 mg"
        let doseExcerpt = ReportEngine.localExcerpt(doseSource)
        precondition(doseExcerpt.hasSuffix(" dose: 10"))
        print("REPRODUCED: 1800-character excerpt ends with synthetic 'dose: 10' while source ends 'dose: 100 mg', without an omission marker")
        let headerSource = "Medication: synthetic A\nSource date: 2026-09-12\nPlan: synthetic follow-up"
        let headerExcerpt = ReportEngine.localExcerpt(headerSource)
        precondition(headerExcerpt == "Plan: synthetic follow-up")
        print("REPRODUCED: ordinary source content before a Source date header is stripped by the fixture-wrapper heuristic")
    }
}
