// Purpose: Define the exact summary/preparation DTOs shared by HTTP routes and the Gemini adapter.
// Inputs: One source document or a visit with candidate records supplied by the native client.
// Outputs: Validated requests and bounded generated summary/overview/question/source-ID response objects.
// Side effects: None. Validation rejects unsafe IDs, excessive candidate counts, text bytes, and malformed fields.
// Boundary: Preparation accepts records only, not the separate quick-reference PatientProfile.

import Foundation
import Vapor

// MARK: - One-document summary request and byte limits
struct GeminiSummaryRequest: Content {
    let recordID: String
    let title: String
    let text: String
    let generateTitle: Bool?
    let date: String?

    init(recordID: String, title: String, text: String, generateTitle: Bool? = nil, date: String? = nil) {
        self.recordID = recordID
        self.title = title
        self.text = text
        self.generateTitle = generateTitle
        self.date = date
    }

    func validate() throws {
        guard Validation.safeID(recordID), GeminiValidation.text(title, maximum: 240),
            GeminiValidation.text(text, maximum: 120_000),
            date.map({ GeminiValidation.text($0, maximum: 40) }) ?? true
        else {
            throw Abort(
                .badRequest,
                reason: "Provide a safe recordID, a title of 1–240 bytes, and source text of 1–120000 bytes.")
        }
    }
}

// MARK: - Visit context and uniquely identified candidate sources
struct GeminiPreparationRequest: Content {
    struct Visit: Codable, Sendable {
        let id: String
        let type: String
        let concern: String
        let goal: String
        let questions: [String]
    }
    struct Record: Codable, Sendable {
        let id: String
        let title: String
        let date: String
        let text: String
        let summary: String
        let version: Int
    }
    let visit: Visit
    let records: [Record]

    func validate() throws {
        guard Validation.safeID(visit.id), GeminiValidation.text(visit.type, maximum: 80),
            GeminiValidation.text(visit.concern, maximum: 6000, allowEmpty: true),
            GeminiValidation.text(visit.goal, maximum: 6000, allowEmpty: true),
            !(visit.concern + visit.goal).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            visit.questions.count <= 20,
            visit.questions.allSatisfy({ GeminiValidation.text($0, maximum: 1000) }),
            (1...100).contains(records.count), Set(records.map(\.id)).count == records.count
        else {
            throw Abort(
                .badRequest,
                reason:
                    "Provide a valid visit concern/goal, at most 20 questions, and 1–100 uniquely identified candidate records."
            )
        }
        var total = 0
        for record in records {
            guard Validation.safeID(record.id), GeminiValidation.text(record.title, maximum: 240),
                GeminiValidation.text(record.date, maximum: 40), record.version >= 1,
                GeminiValidation.text(record.text, maximum: 120_000),
                GeminiValidation.text(record.summary, maximum: 8000, allowEmpty: true)
            else {
                throw Abort(
                    .badRequest,
                    reason:
                        "Candidate records need safe IDs, source text, dates, positive versions, and bounded title/summary fields."
                )
            }
            total += record.text.utf8.count + record.summary.utf8.count
        }
        guard total <= 500_000 else {
            throw Abort(
                .payloadTooLarge,
                reason: "Candidate source text and summaries exceed 500000 bytes. Choose fewer records.")
        }
    }
}

// MARK: - Model-labelled results validated by the service
struct GeminiSummaryResponse: Content {
    let summary: String
    let model: String
    let title: String?

    init(summary: String, model: String, title: String? = nil) {
        self.summary = summary
        self.model = model
        self.title = title
    }
}
struct GeminiPreparationResponse: Content {
    let overview: String
    let questions: [String]
    let selectedRecordIDs: [String]
    let model: String
}

// MARK: - Shared text validation in UTF-8 bytes
enum GeminiValidation {
    static func text(_ value: String, maximum: Int, allowEmpty: Bool = false) -> Bool {
        value.utf8.count <= maximum && !value.contains("\0")
            && (allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
