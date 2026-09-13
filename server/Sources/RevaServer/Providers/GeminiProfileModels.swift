// Purpose: Define exact, bounded report inputs and source-linked medical-profile extraction results.
// Inputs: Untrusted report JSON and validated generated facts.
// Outputs: Codable profile request/response contracts shared with the browser endpoint.
// Side effects: None; invalid and oversized sources fail before any provider call.

import Foundation
import Vapor

// MARK: - Complete uniquely identified source reports
struct GeminiProfileRequest: Content {
    struct Record: Codable, Sendable {
        let id: String
        let version: Int
        let title: String
        let date: String
        let text: String

        init(id: String, version: Int, title: String, date: String, text: String) {
            self.id = id
            self.version = version
            self.title = title
            self.date = date
            self.text = text
        }

        init(from decoder: Decoder) throws {
            try ProfileCodingKey.require(["id", "version", "title", "date", "text"], in: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            version = try values.decode(Int.self, forKey: .version)
            title = try values.decode(String.self, forKey: .title)
            date = try values.decode(String.self, forKey: .date)
            text = try values.decode(String.self, forKey: .text)
        }
    }
    let records: [Record]

    init(records: [Record]) { self.records = records }

    init(from decoder: Decoder) throws {
        try ProfileCodingKey.require(["records"], in: decoder)
        records = try decoder.container(keyedBy: CodingKeys.self).decode([Record].self, forKey: .records)
    }

    func validate() throws {
        guard (1...100).contains(records.count), Set(records.map(\.id)).count == records.count else {
            throw Abort(
                .badRequest,
                reason: "Provide 1–100 uniquely identified source reports for the medical profile.")
        }
        var bytes = 0
        for record in records {
            guard Validation.safeID(record.id), record.version >= 1, record.version <= 9_007_199_254_740_991,
                GeminiValidation.text(record.title, maximum: 240),
                GeminiValidation.text(record.date, maximum: 40),
                GeminiValidation.text(record.text, maximum: 100_000)
            else {
                throw Abort(
                    .badRequest,
                    reason:
                        "Reports need safe IDs, positive versions, titles, dates and source text of at most 100000 UTF-8 bytes."
                )
            }
            bytes += record.text.utf8.count
        }
        guard bytes <= 200_000 else {
            throw Abort(
                .payloadTooLarge,
                reason:
                    "Medical-profile source text exceeds 200000 UTF-8 bytes. No reports were omitted or changed."
            )
        }
    }
}

// MARK: - Bounded medical facts with mandatory supporting source identities
struct GeminiProfileFact: Codable, Sendable, Equatable {
    let text: String
    let recordIDs: [String]
}

struct GeminiProfileResponse: Content {
    let allergies: [GeminiProfileFact]
    let medications: [GeminiProfileFact]
    let conditions: [GeminiProfileFact]
    let surgeriesAndImplants: [GeminiProfileFact]
    let careNotes: [GeminiProfileFact]
    let model: String
}

// MARK: - Reject unknown input keys instead of silently discarding them
private struct ProfileCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }

    static func require(_ keys: Set<String>, in decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Self.self)
        guard Set(values.allKeys.map(\.stringValue)) == keys else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unexpected medical-profile source fields."))
        }
    }
}
