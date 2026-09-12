import Foundation

extension AppStore {
    func save(_ visit: Visit) throws {
        var visit = visit
        visit.report?.questions = visit.questions; visit.report?.notes = visit.notes
        try mutate { data in if let i = data.visits.firstIndex(where: { $0.id == visit.id }) { data.visits[i] = visit } else { data.visits.append(visit) } }
    }
    func generateReport(_ id: String) throws {
        try mutate { data in guard let i = data.visits.firstIndex(where: { $0.id == id }) else { return }; let report = ReportEngine.generate(visit: data.visits[i], records: data.records); data.visits[i].questions = report.questions; data.visits[i].report = report }
    }
}
