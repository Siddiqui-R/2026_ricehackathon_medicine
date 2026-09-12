// Purpose: Provide the account primitives shared by auth routes and the bearer middleware.
// Inputs: Raw sign-up/log-in fields, plaintext passwords, bcrypt hashes, session tokens, and the app thread pool.
// Outputs: Normalized/validated fields, bcrypt hashes, opaque session tokens plus their SHA-256 hex, and throttle verdicts.
// Side effects: Bcrypt work runs on the NIO thread pool, never on an event loop. Nothing here logs or stores plaintext.
// Ownership: Policy limits mirror the implementation contract; the same rules apply to local and PostgreSQL storage.

import Foundation
import Vapor

// MARK: - Field normalization and password policy
/// Every failure names the offending field so the client can highlight it.
enum AccountPolicy {
    static let minimumPasswordBytes = 10
    static let maximumPasswordBytes = 72
    static let maximumLiveSessions = 20
    static let sessionTouchInterval: TimeInterval = 5 * 60

    /// Trim, lowercase, and require a single @ with a dotted domain; 3–254 characters and no control characters.
    static func normalizeEmail(_ raw: String) throws -> String {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...254).contains(email.count), !containsControlCharacters(email),
            email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        else {
            throw Abort(.badRequest, reason: "email must be a valid address of 3–254 characters.")
        }
        return email
    }

    /// Trim and require 1–80 characters without control characters.
    static func normalizeName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count), !containsControlCharacters(name) else {
            throw Abort(.badRequest, reason: "name must be 1–80 characters without control characters.")
        }
        return name
    }

    /// Passwords are used verbatim: 10–72 UTF-8 bytes (the bcrypt limit), no line breaks, never the email itself.
    static func validatePassword(_ password: String, email: String) throws {
        let bytes = password.utf8.count
        guard (minimumPasswordBytes...maximumPasswordBytes).contains(bytes) else {
            throw Abort(.badRequest, reason: "password must be 10–72 bytes.")
        }
        guard !password.contains("\r"), !password.contains("\n") else {
            throw Abort(.badRequest, reason: "password cannot contain line breaks.")
        }
        guard password.lowercased() != email.lowercased(),
            password.lowercased() != email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else {
            throw Abort(.badRequest, reason: "password cannot be the same as the email.")
        }
    }

    /// The session label is the User-Agent reduced to printable ASCII, at most 120 characters, empty when absent.
    static func sessionLabel(userAgent: String?) -> String {
        guard let userAgent else { return "" }
        let printable = userAgent.unicodeScalars.filter { (32...126).contains($0.value) }
        return String(String.UnicodeScalarView(printable).prefix(120))
    }

    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 || (128...159).contains($0.value) }
    }
}

// MARK: - Random identifiers and opaque session tokens
enum AccountIdentifiers {
    /// u_ + 24 lowercase hex characters from 12 random bytes; satisfies Validation.safeID.
    static func userID() -> String {
        "u_" + [UInt8].random(count: 12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Session tokens are opaque: rs_ + 43 base64url characters (32 random bytes). Only the SHA-256 hex is stored.
enum SessionToken {
    static let prefix = "rs_"
    static let length = 46
    private static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    static func generate() -> String {
        let encoded = Data([UInt8].random(count: 32)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + encoded
    }

    static func isWellFormed(_ token: String) -> Bool {
        token.count == length && token.hasPrefix(prefix)
            && token.dropFirst(prefix.count).allSatisfy(alphabet.contains)
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Bcrypt on the thread pool with a fixed dummy hash for unknown emails
/// Cost is injectable so tests stay fast; production uses 12. The dummy hash uses the same cost so timing matches.
struct PasswordHasher: Sendable {
    let cost: Int
    let threadPool: NIOThreadPool
    private let dummy = DummyHash()

    init(cost: Int, threadPool: NIOThreadPool) {
        self.cost = cost
        self.threadPool = threadPool
    }

    func hash(_ password: String) async throws -> String {
        let cost = self.cost
        return try await threadPool.runIfActive { try Bcrypt.hash(password, cost: cost) }
    }

    func verify(_ password: String, against hash: String) async throws -> Bool {
        try await threadPool.runIfActive { try Bcrypt.verify(password, created: hash) }
    }

    /// Runs a full verification against a per-process dummy hash so an unknown email costs as much as a wrong password.
    func verifyAgainstDummy(_ password: String) async {
        guard let hash = try? await dummy.value(using: self) else { return }
        _ = try? await verify(password, against: hash)
    }

    private actor DummyHash {
        private var cached: String?
        func value(using hasher: PasswordHasher) async throws -> String {
            if let cached { return cached }
            let hash = try await hasher.hash(SessionToken.generate())
            cached = hash
            return hash
        }
    }
}

// MARK: - Per-email log-in failure throttle
/// In-memory and per process: 8 failures per normalized email within 15 minutes, at most 10,000 tracked keys.
actor LoginThrottle {
    static let maximumFailures = 8
    static let window: TimeInterval = 15 * 60
    static let maximumKeys = 10_000

    private struct Entry {
        var failures: Int
        var windowStart: Date
    }
    private var entries: [String: Entry] = [:]

    /// Returns the number of seconds to wait when the key is locked, nil when a log-in attempt may proceed.
    func retryAfter(_ key: String, now: Date = Date()) -> Int? {
        guard let entry = entries[key] else { return nil }
        let elapsed = now.timeIntervalSince(entry.windowStart)
        guard elapsed < Self.window else {
            entries[key] = nil
            return nil
        }
        guard entry.failures >= Self.maximumFailures else { return nil }
        return max(1, Int((Self.window - elapsed).rounded(.up)))
    }

    func recordFailure(_ key: String, now: Date = Date()) {
        if var entry = entries[key], now.timeIntervalSince(entry.windowStart) < Self.window {
            entry.failures += 1
            entries[key] = entry
            return
        }
        if entries[key] == nil { makeRoom(now: now) }
        entries[key] = Entry(failures: 1, windowStart: now)
    }

    func clear(_ key: String) { entries[key] = nil }

    var trackedKeyCount: Int { entries.count }

    /// Drop expired windows first; if the table is still full, evict the oldest window.
    private func makeRoom(now: Date) {
        guard entries.count >= Self.maximumKeys else { return }
        entries = entries.filter { now.timeIntervalSince($0.value.windowStart) < Self.window }
        while entries.count >= Self.maximumKeys,
            let oldest = entries.min(by: { $0.value.windowStart < $1.value.windowStart })
        {
            entries[oldest.key] = nil
        }
    }
}
