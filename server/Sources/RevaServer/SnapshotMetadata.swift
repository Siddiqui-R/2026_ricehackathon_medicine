// Purpose: Validate additive date/title provenance without reinterpreting legacy clinical snapshots.
// Inputs: Structurally validated snapshot objects with optional record and recording metadata.
// Outputs: Acceptance or a sanitized validation error; original timestamps remain unchanged.
// Side effects: None. Missing/null metadata remains compatible with older clients.

import Foundation
import Vapor

// MARK: - Optional provenance fields only; unrelated legacy snapshot fields remain untouched
extension Validation {
    static func snapshotMetadata(_ snapshot: [String: JSONValue]) throws {
        func optionalEnum(_ value: JSONValue?, choices: [String]) -> Bool {
            guard let value, value != .null else { return true }
            guard case .string(let string) = value else { return false }
            return choices.contains(string)
        }
        func optionalDate(_ value: JSONValue?) -> Bool {
            guard let value, value != .null else { return true }
            guard case .string(let string) = value else { return false }
            return validMetadataDate(string)
        }
        for key in ["records", "recordings"] {
            guard case .array(let values) = snapshot[key] else { continue }
            for value in values {
                guard case .object(let object) = value else { continue }
                let valid: Bool
                if key == "records" {
                    valid =
                        optionalEnum(
                            object["dateSource"], choices: ["document", "observed", "recorded", "added"])
                        && optionalDate(object["summaryGeneratedAt"])
                } else {
                    valid =
                        optionalEnum(object["titleSource"], choices: ["user", "date", "ai"])
                        && ["capturedAt", "savedAt", "aiSummaryGeneratedAt"].allSatisfy {
                            optionalDate(object[$0])
                        }
                }
                guard valid else {
                    throw Abort(
                        .badRequest,
                        reason: "Invalid optional record or recording date/title provenance metadata.")
                }
            }
        }
    }

    // MARK: - Strict ISO date/instant syntax and Gregorian validity prevent implicit rollover
    static func validMetadataDate(_ value: String) -> Bool {
        guard value.utf8.count <= 40,
            value.range(
                of:
                    #"^\d{4}-\d{2}-\d{2}(?:T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d))?\z"#,
                options: .regularExpression) != nil
        else { return false }
        let parts = value.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            year >= 1, (1...12).contains(month)
        else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }
}
