// Purpose: Apply provider summaries and prepare briefs without losing newer source edits.
// Inputs: Record or visit ID and the current candidate records.
// Outputs: A saved labeled summary/report or a user-visible failure.
// Side effects: Calls the configured server and writes only results matching captured source state.

import Foundation

// MARK: - Single-record summarization
// Capture source identity/version before awaiting; discard results when the record changed.
extension AppStore {
    func summarizeWithAI(_ id: String) async {
        guard !isProviderBusy, let original = record(id) else { return }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        do {
            var input = original
            input.summary = ReportEngine.currentSummary(original)
            let result = try await providerClient().summarize(input)
            guard context == providerContext else { return }
            try Task.checkCancellation()
            guard var latest = record(id), latest.text == original.text, latest.version == original.version
            else {
                throw RevaError.invalid(
                    "The record changed while summarizing. Your edits were kept; retry with the current source."
                )
            }
            guard !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RevaError.invalid("The AI returned no summary. Your local excerpt was kept.")
            }
            latest.summary = result.summary
            latest.summaryModel = result.model
            try save(latest)
            notice = "AI summary saved. Review it against the original source."
        } catch {
            guard context == providerContext else { return }
            errorMessage = error.localizedDescription
        }
    }
    // MARK: - Visit brief generation
    // Choose local or connected generation, validate selected IDs and protect user questions/notes.
    @discardableResult func generatePreferredReport(_ id: String) async -> Bool {
        guard useConnectedAI else { return perform { try generateReport(id) } }
        guard !isProviderBusy else {
            notice = "A connected request is still running. Try creating the brief when it finishes."
            return false
        }
        guard let original = visit(id) else { return false }
        let context = providerContext
        isProviderBusy = true
        defer { isProviderBusy = false }
        let sources = records
        let signature = ReportEngine.signature(visit: original, records: sources)
        do {
            let candidates = sources.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.map { record in
                // Use the same safe preview as source display without rewriting saved records.
                var candidate = record
                candidate.summary = ReportEngine.currentSummary(record)
                return candidate
            }
            guard !candidates.isEmpty else {
                throw RevaError.invalid(
                    "Add readable source text before using connected preparation, or turn off connected AI to prepare locally."
                )
            }
            let result = try await providerClient().prepare(original, records: candidates)
            guard context == providerContext else { return false }
            try Task.checkCancellation()
            guard var latest = visit(id), signature == ReportEngine.signature(visit: latest, records: records)
            else {
                throw RevaError.invalid(
                    "Sources or visit details changed during preparation. Your edits were kept; regenerate using the current records."
                )
            }
            let known = Set(sources.map(\.id))
            guard Set(result.selectedRecordIDs).isSubset(of: known) else {
                throw RevaError.invalid("The AI returned an unknown source. No report was saved.")
            }
            let selected = Set(result.selectedRecordIDs).union(latest.pinnedRecordIDs)
            var quoteVisit = latest
            quoteVisit.pinnedRecordIDs = Array(selected)
            var report = ReportEngine.generate(
                visit: quoteVisit, records: sources.filter { selected.contains($0.id) })
            report.sourceSignature = signature
            report.generationModel = result.model
            report.isDemo = false
            report.sections.insert(
                ReportSection(
                    title: "AI preparation overview · review with your clinician", body: result.overview,
                    sources: []), at: min(1, report.sections.count))
            // Existing/user-edited questions remain authoritative when refreshing a brief.
            if original.report == nil && original.questions.isEmpty && latest.questions == original.questions
            {
                latest.questions = result.questions
            }
            report.questions = latest.questions
            report.notes = latest.notes
            latest.report = report
            try save(latest)
            notice = "AI-assisted brief ready. Review its overview and original source excerpts."
            return true
        } catch {
            guard context == providerContext else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
