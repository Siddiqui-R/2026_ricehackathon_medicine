// Purpose: Define the server wire/storage contracts and shared structural resource limits.
// Inputs: Codable JSON values, snapshot envelopes, flat attachment metadata, and original bytes.
// Outputs: Forward-compatible aggregate values, storage interfaces, and validation errors for malformed/oversized input.
// Side effects: No I/O. OwnerDocument records bounded in-memory audit entries before a store persists them.
// Boundary: Snapshot validation checks structure/size, while the native client owns detailed medical domain rules.

import Foundation
import Vapor

// MARK: - Generic aggregate JSON encoding
// Integers remain integers so schema versions and revisions survive round trips.
public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Int64.self) {
            self = .integer(decoded)
        } else if let decoded = try? value.decode(Double.self) {
            self = .number(decoded)
        } else if let decoded = try? value.decode(String.self) {
            self = .string(decoded)
        } else if let decoded = try? value.decode([JSONValue].self) {
            self = .array(decoded)
        } else {
            self = .object(try value.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .integer(let integer): try value.encode(integer)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
}

// MARK: - HTTP state and status envelopes
public struct StateEnvelope: Content, Equatable {
    public let revision: Int
    public let snapshot: JSONValue
}

struct StateWrite: Content {
    let baseRevision: Int
    let snapshot: JSONValue
}
struct RevisionResponse: Content { let revision: Int }
struct HealthResponse: Content {
    let status: String
    let storage: String
    let isDemo: Bool
}
struct ErrorResponse: Content {
    let error: Bool
    let reason: String
}

// MARK: - Original bytes and bounded aggregate audit metadata
public struct StoredAttachment: Codable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let contentType: String
    public let data: Data
    public let updatedAt: Date
}

struct AuditEntry: Codable, Sendable {
    let mutationID: UUID
    let action: String
    let revision: Int
    let createdAt: Date
}

// MARK: - Local owner aggregate and tombstone revision
// A missing snapshot can retain a revision so stale clients cannot silently resurrect deleted state.
struct OwnerDocument: Codable, Sendable {
    var formatVersion = 1
    var revision = 0
    var snapshot: JSONValue?
    var attachments: [String: StoredAttachment] = [:]
    var audit: [AuditEntry] = []

    mutating func record(_ action: String) {
        audit.append(.init(mutationID: UUID(), action: action, revision: revision, createdAt: Date()))
        if audit.count > 128 { audit.removeFirst(audit.count - 128) }
    }
}

// MARK: - Store failure vocabulary and interchangeable storage interface
enum StoreError: Error, Sendable {
    case conflict(Int)
    case missing(Int)
    case attachmentMissing, quota, corrupt
}

public protocol RevaStore: Sendable {
    func health() async throws
    func getState(owner: String) async throws -> StateEnvelope
    func putState(owner: String, baseRevision: Int, snapshot: JSONValue) async throws -> Int
    func deleteState(owner: String) async throws -> Int
    func putAttachment(owner: String, attachment: StoredAttachment) async throws
    func getAttachment(owner: String, id: String) async throws -> StoredAttachment
    func deleteAttachment(owner: String, id: String) async throws
}

// MARK: - Shared structural, path, content-type, and size limits
enum Validation {
    static let maxSnapshotBytes = 4 * 1024 * 1024
    static let maxAttachmentBytes = 16 * 1024 * 1024
    static let maxOwnerAttachmentBytes = 64 * 1024 * 1024
    static let maxAttachmentCount = 128
    static let contentTypes: Set<String> = [
        "application/pdf", "text/plain", "image/png", "image/jpeg", "image/heic", "image/heif", "audio/mp4",
        "audio/x-m4a", "audio/m4a", "audio/mpeg", "audio/wav", "audio/x-wav", "audio/webm", "audio/ogg",
        "application/octet-stream",
    ]

    static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 80
            && value.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
                    || $0 == 95
            }
    }

    // MARK: - Snapshot envelope validation without clinical interpretation
    static func snapshot(_ value: JSONValue) throws {
        guard case .object(let object) = value,
            object["schemaVersion"] == .integer(1),
            case .object(let profile) = object["profile"], !profile.isEmpty
        else {
            throw Abort(
                .badRequest, reason: "Snapshot must have schemaVersion 1 and a nonempty profile object.")
        }
        for key in ["records", "visits", "bookings", "recordings"] {
            guard case .array(let items) = object[key], items.count <= 5000,
                items.allSatisfy({
                    if case .object = $0 { return true }
                    return false
                })
            else {
                throw Abort(
                    .badRequest,
                    reason:
                        "Snapshot requires records, visits, bookings, and recordings arrays of objects (maximum 5000 each)."
                )
            }
        }
        try checkDepth(value, depth: 0)
        guard try JSONEncoder().encode(value).count <= maxSnapshotBytes else {
            throw Abort(.payloadTooLarge, reason: "Snapshot exceeds 4 MiB.")
        }
    }

    static func checkDepth(_ value: JSONValue, depth: Int) throws {
        guard depth <= 32 else { throw Abort(.badRequest, reason: "Snapshot nesting exceeds 32 levels.") }
        switch value {
        case .object(let object): for child in object.values { try checkDepth(child, depth: depth + 1) }
        case .array(let array): for child in array { try checkDepth(child, depth: depth + 1) }
        default: break
        }
    }

    // MARK: - Flat metadata and original-byte validation
    static func attachment(_ attachment: StoredAttachment) throws {
        guard safeID(attachment.id) else {
            throw Abort(
                .badRequest,
                reason:
                    "Attachment ID must contain only ASCII letters, numbers, hyphens or underscores (1–80 characters)."
            )
        }
        let name = attachment.filename
        guard !name.isEmpty, name.utf8.count <= 180, name != ".", name != "..", !name.hasPrefix("."),
            name == name.trimmingCharacters(in: .whitespaces),
            name.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || [32, 40, 41, 45, 46, 95].contains($0)
            })
        else {
            throw Abort(
                .badRequest,
                reason:
                    "X-Filename must be a flat ASCII filename using letters, numbers, spaces, dots, hyphens, underscores or parentheses (1–180 characters)."
            )
        }
        guard contentTypes.contains(attachment.contentType) else {
            throw Abort(.unsupportedMediaType, reason: "Unsupported attachment Content-Type.")
        }
        guard !attachment.data.isEmpty else { throw Abort(.badRequest, reason: "Attachment body is empty.") }
        guard attachment.data.count <= maxAttachmentBytes else {
            throw Abort(.payloadTooLarge, reason: "Attachment exceeds 16 MiB.")
        }
    }
}
