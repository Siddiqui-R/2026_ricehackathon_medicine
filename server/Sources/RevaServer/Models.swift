// Purpose: Define the server wire/storage contracts, account/session records, and shared structural resource limits.
// Inputs: Codable JSON values, snapshot envelopes, flat attachment metadata, original bytes, and account records.
// Outputs: Forward-compatible aggregate values, storage interfaces, auth envelopes, and validation errors for malformed input.
// Side effects: No I/O. OwnerDocument records bounded in-memory audit entries before a store persists them.
// Boundary: Snapshot validation checks structure/size, while the native client owns detailed medical domain rules.
// Ownership: UserRecord.passwordHash is always a bcrypt hash and SessionRecord.tokenHash a SHA-256 hex; never plaintext.

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

// MARK: - Account and session records
// The owner ID of an account is its user ID, so existing owner-scoped routes work unchanged.
public struct UserRecord: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let name: String
    public let passwordHash: String
    public let createdAt: Date
    public let passwordUpdatedAt: Date

    public init(
        id: String, email: String, name: String, passwordHash: String, createdAt: Date,
        passwordUpdatedAt: Date
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.passwordHash = passwordHash
        self.createdAt = createdAt
        self.passwordUpdatedAt = passwordUpdatedAt
    }

    func replacingPassword(hash: String, at date: Date) -> UserRecord {
        UserRecord(
            id: id, email: email, name: name, passwordHash: hash, createdAt: createdAt,
            passwordUpdatedAt: date)
    }
}

public struct SessionRecord: Codable, Sendable, Equatable {
    public let id: UUID
    public let tokenHash: String
    public let userID: String
    public let label: String
    public let createdAt: Date
    public let lastUsedAt: Date
    public let expiresAt: Date
    public let revokedAt: Date?

    public init(
        id: UUID, tokenHash: String, userID: String, label: String, createdAt: Date, lastUsedAt: Date,
        expiresAt: Date, revokedAt: Date?
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.userID = userID
        self.label = label
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
    }

    /// A session is live only while it is neither revoked nor past its expiry.
    func isLive(at now: Date) -> Bool { revokedAt == nil && expiresAt > now }

    func touched(at date: Date) -> SessionRecord {
        SessionRecord(
            id: id, tokenHash: tokenHash, userID: userID, label: label, createdAt: createdAt,
            lastUsedAt: date,
            expiresAt: expiresAt, revokedAt: revokedAt)
    }

    func revoked(at date: Date) -> SessionRecord {
        SessionRecord(
            id: id, tokenHash: tokenHash, userID: userID, label: label, createdAt: createdAt,
            lastUsedAt: lastUsedAt, expiresAt: expiresAt, revokedAt: revokedAt ?? date)
    }
}

// MARK: - Account failure vocabulary and account storage interface
enum AccountError: Error, Sendable {
    case emailTaken, userMissing, sessionMissing
}

public protocol AccountStore: Sendable {
    /// Throws AccountError.emailTaken on a duplicate normalized email (case-insensitive).
    func createUser(_ user: UserRecord) async throws
    func user(email: String) async throws -> UserRecord?
    func user(id: String) async throws -> UserRecord?
    func updatePassword(userID: String, hash: String, at: Date) async throws
    /// Atomically checks the verified password and presenting live session, changes the password,
    /// and revokes every other session. Returns false without writes if verification became stale.
    func changePassword(
        userID: String, verifiedPasswordHash: String, newHash: String, keepingSessionID: UUID, at: Date
    ) async throws -> Bool
    /// Removes the user, every session, and the owner's state/attachments/audit rows.
    func deleteUser(id: String) async throws
    /// Enforces the 20-live-sessions-per-user cap by revoking the oldest sessions.
    func createSession(_ session: SessionRecord) async throws
    /// Checks the verified password and inserts under the same lock as password changes, so an
    /// in-flight log-in cannot issue a session after its password was replaced. False makes no writes.
    func createSession(_ session: SessionRecord, verifiedPasswordHash: String) async throws -> Bool
    /// Returns nil when no live session matches; revoked and expired sessions are never returned.
    func session(tokenHash: String) async throws -> (SessionRecord, UserRecord)?
    func touchSession(id: UUID, at: Date) async throws
    func revokeSession(id: UUID) async throws
    func revokeSessions(userID: String, except: UUID?) async throws
}

// MARK: - Authenticated identity carried through a request
// Static workspace tokens carry no session/user; account sessions carry both and use the user ID as owner.
struct OwnerIdentity: Authenticatable {
    let id: String
    var session: SessionRecord? = nil
    var user: UserRecord? = nil
}

// MARK: - Public auth envelopes
// Dates encode as ISO-8601 through Vapor's JSON content configuration.
public struct AuthUser: Content, Equatable {
    public let id: String
    public let email: String
    public let name: String
    public let createdAt: Date

    public init(_ user: UserRecord) {
        id = user.id
        email = user.email
        name = user.name
        createdAt = user.createdAt
    }
}

public struct AuthSessionEnvelope: Content {
    public let token: String
    public let expiresAt: Date
    public let user: AuthUser

    public init(token: String, expiresAt: Date, user: AuthUser) {
        self.token = token
        self.expiresAt = expiresAt
        self.user = user
    }
}

public struct AuthSessionSummary: Content, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let lastUsedAt: Date

    public init(_ session: SessionRecord) {
        id = session.id
        createdAt = session.createdAt
        expiresAt = session.expiresAt
        lastUsedAt = session.lastUsedAt
    }
}

public struct AuthIdentityResponse: Content {
    public let kind: String
    public let owner: String
    public let user: AuthUser?
    public let session: AuthSessionSummary?

    public init(kind: String, owner: String, user: AuthUser?, session: AuthSessionSummary?) {
        self.kind = kind
        self.owner = owner
        self.user = user
        self.session = session
    }
}

struct SignupRequest: Content {
    let email: String
    let password: String
    let name: String
}
struct LoginRequest: Content {
    let email: String
    let password: String
}
struct PasswordChangeRequest: Content {
    let currentPassword: String
    let newPassword: String
}
struct AccountDeleteRequest: Content {
    let password: String
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
        try snapshotMetadata(object)
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
