// Purpose: Keep appointment details and report questions synchronized.
// Inputs: Visit edits or an existing visit ID for local preparation.
// Outputs: Saved visits and local reports with authoritative user questions/notes.
// Side effects: Writes the snapshot through mutate; no HTTP requests.

import Foundation

// MARK: - Visit edits
// User questions and notes are authoritative and mirrored into any existing report.
extension AppStore {
    func save(_ visit: Visit) throws {
        var visit = visit
        visit.report?.questions = visit.questions
        visit.report?.notes = visit.notes
        try mutate { data in
            if let i = data.visits.firstIndex(where: { $0.id == visit.id }) {
                data.visits[i] = visit
            } else {
                data.visits.append(visit)
            }
        }
    }
    // MARK: - Local preparation
    // Generate evidence from the current source pool and persist it with the visit.
    func generateReport(_ id: String) throws {
        try mutate { data in
            guard let i = data.visits.firstIndex(where: { $0.id == id }) else { return }
            let report = ReportEngine.generate(visit: data.visits[i], records: data.records)
            data.visits[i].questions = report.questions
            data.visits[i].report = report
        }
    }
}
