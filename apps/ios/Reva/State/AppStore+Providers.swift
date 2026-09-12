import Foundation

/// Integration captain owns this boundary; feature modules call these focused operations.
extension AppStore {
    func providerClient() throws -> ProviderClient {
        try ProviderClient(url: connectionURL, token: connectionToken)
    }
    func checkProviders() async {
        do {
            providerStatus = try await providerClient().status()
            UserDefaults.standard.set(connectionURL, forKey: "serverURL")
            notice = "Service configuration checked. Only configured connections can be used."
        } catch { providerStatus = nil; errorMessage = error.localizedDescription }
    }
    func summarizeWithAI(_ id: String) async {
        guard !isProviderBusy, let original = record(id) else { return }
        isProviderBusy = true; defer { isProviderBusy = false }
        do {
            let result = try await providerClient().summarize(original)
            guard var latest = record(id), latest.text == original.text, latest.version == original.version else {
                throw RevaError.invalid("The record changed while summarizing. Your edits were kept; retry with the current source.")
            }
            guard !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RevaError.invalid("The AI returned no summary. Your local excerpt was kept.") }
            latest.summary = result.summary; latest.summaryModel = result.model
            try save(latest); notice = "AI summary saved. Review it against the original source."
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func generatePreferredReport(_ id: String) async -> Bool {
        guard useConnectedAI else { return perform { try generateReport(id) } }
        guard !isProviderBusy, let original = visit(id) else { return false }
        isProviderBusy = true; defer { isProviderBusy = false }
        let sources = records
        let signature = ReportEngine.signature(visit: original, records: sources)
        do {
            let candidates = sources.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !candidates.isEmpty else { throw RevaError.invalid("Add readable source text before using connected preparation, or turn off connected AI to prepare locally.") }
            let result = try await providerClient().prepare(original, records: candidates)
            guard var latest = visit(id), signature == ReportEngine.signature(visit: latest, records: records) else {
                throw RevaError.invalid("Sources or visit details changed during preparation. Your edits were kept; regenerate using the current records.")
            }
            let known = Set(sources.map(\.id))
            guard Set(result.selectedRecordIDs).isSubset(of: known) else { throw RevaError.invalid("The AI returned an unknown source. No report was saved.") }
            let selected = Set(result.selectedRecordIDs).union(latest.pinnedRecordIDs)
            var quoteVisit = latest; quoteVisit.pinnedRecordIDs = Array(selected)
            var report = ReportEngine.generate(visit: quoteVisit, records: sources.filter { selected.contains($0.id) })
            report.sourceSignature = signature; report.generationModel = result.model; report.isDemo = false
            report.sections.insert(ReportSection(title: "AI preparation overview · review with your clinician", body: result.overview, sources: []), at: min(1, report.sections.count))
            // Existing/user-edited questions remain authoritative when refreshing a brief.
            if original.report == nil && original.questions.isEmpty && latest.questions == original.questions { latest.questions = result.questions }
            report.questions = latest.questions; report.notes = latest.notes; latest.report = report
            try save(latest); notice = "AI-assisted brief ready. Review its overview and original source excerpts."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func transcribeRecording(_ id: String) async {
        guard !isProviderBusy, let original = recording(id), !original.isSample, let name = original.audioFilename, let url = sourceURL(name) else { return }
        isProviderBusy = true; defer { isProviderBusy = false }
        do {
            let result = try await providerClient().transcribe(bytes: Data(contentsOf: url), filename: name)
            guard var latest = recording(id), latest.audioFilename == original.audioFilename, latest.segments == original.segments else {
                throw RevaError.invalid("The recording or transcript changed. Your edits were kept; retry from the current recording.")
            }
            guard !result.text.isEmpty, !result.segments.isEmpty,
                  Set(result.segments.map(\.id)).count == result.segments.count,
                  result.segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= original.duration + 5 && !$0.text.isEmpty }) else {
                throw RevaError.invalid("The transcript contained invalid or missing timestamps. Your audio was kept.")
            }
            latest.segments = result.segments; latest.transcriptionModel = result.model; latest.status = "transcribed"
            try save(latest)
            if records.contains(where: { $0.sourceRecordingID == id || $0.id == "memory-" + id }) { try saveMemory(recordingID: id) }
            notice = "Transcript saved. Review the words and speaker attribution before using it."
        } catch { errorMessage = error.localizedDescription }
    }
    func placeLiveCall(_ request: BookingRequest) async {
        guard !isProviderBusy else { return }; isProviderBusy = true; defer { isProviderBusy = false }
        do {
            var request = request; request.isLive = true; request.status = "starting"
            try save(request)
            let result = try await providerClient().startCall(.init(requestID: request.id, clinic: request.clinic, phone: request.phone, reason: request.reason,
                earliest: request.earliest, latest: request.latest, timeZone: request.timeZone, preferences: request.preferences, patientName: snapshot?.profile.name ?? "", consent: true))
            try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == request.id }) {
                data.bookings[i].providerConversationID = result.conversationID; data.bookings[i].status = result.status
            } }
            notice = "Call request accepted. Check status and review the outcome; Reva has not confirmed an appointment."
        } catch {
            perform { try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == request.id }) { data.bookings[i].status = "unknown" } } }
            errorMessage = error.localizedDescription
        }
    }
    func refreshLiveCall(_ id: String) async {
        guard !isProviderBusy else { return }; isProviderBusy = true; defer { isProviderBusy = false }
        do {
            let result = try await providerClient().callStatus(requestID: id)
            try mutate { data in if let i = data.bookings.firstIndex(where: { $0.id == id }) {
                data.bookings[i].providerConversationID = result.conversationID; data.bookings[i].status = result.status; data.bookings[i].providerTranscript = result.transcript
            } }
        } catch { errorMessage = error.localizedDescription }
    }
}
