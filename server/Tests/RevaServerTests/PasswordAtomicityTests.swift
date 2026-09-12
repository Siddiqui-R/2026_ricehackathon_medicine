// Purpose: Prove password changes and verified session issuance remain safe across competing requests.
// Inputs: Temporary local registries, inexpensive synthetic bcrypt passwords and deterministic HTTP interleavings.
// Outputs: Assertions that stale verification never changes a password or leaves a live session behind.
// Side effects: Temporary files and in-process Vapor requests only; no database or provider connections.

import Foundation
import Testing
import VaporTesting

@testable import RevaServer

private let atomicityPassword = "original-test-password"
private let replacementPassword = "replacement-test-password"

private struct PasswordFixture: Sendable {
    let store: LocalFileStore
    let directory: URL
    let user: UserRecord
    let presenting: SessionRecord
    let other: SessionRecord
    let replacementHash: String
    var registry: URL { directory.appendingPathComponent(".accounts.json") }
}

private func sessionFor(_ user: UserRecord, expiresAt: Date? = nil, revokedAt: Date? = nil) -> SessionRecord {
    let now = Date()
    return SessionRecord(
        id: UUID(), tokenHash: SessionToken.hash(SessionToken.generate()), userID: user.id, label: "test",
        createdAt: now, lastUsedAt: now, expiresAt: expiresAt ?? now.addingTimeInterval(3600),
        revokedAt: revokedAt)
}

private func withPasswordFixture(_ test: (PasswordFixture) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "reva-password-atomicity-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LocalFileStore(directory: directory)
    let now = Date()
    let user = UserRecord(
        id: AccountIdentifiers.userID(), email: "atomicity@example.com", name: "Atomicity Test",
        passwordHash: try Bcrypt.hash(atomicityPassword, cost: 4), createdAt: now, passwordUpdatedAt: now)
    let presenting = sessionFor(user)
    let other = sessionFor(user)
    try await store.createUser(user)
    try await store.createSession(presenting)
    try await store.createSession(other)
    try await test(
        PasswordFixture(
            store: store, directory: directory, user: user, presenting: presenting, other: other,
            replacementHash: try Bcrypt.hash(replacementPassword, cost: 4)))
}

@Suite("Atomic password changes and session issuance")
struct PasswordAtomicityTests {
    @Test func passwordChangeRevokesOtherSessionsAndRejectsStaleVerificationWithoutWrites() async throws {
        try await withPasswordFixture { fixture in
            let store = fixture.store
            let now = Date()
            let unrelated = UserRecord(
                id: AccountIdentifiers.userID(), email: "unrelated@example.com", name: "Unrelated",
                passwordHash: fixture.user.passwordHash, createdAt: now, passwordUpdatedAt: now)
            let unrelatedSession = sessionFor(unrelated)
            try await store.createUser(unrelated)
            try await store.createSession(unrelatedSession)
            #expect(
                try await store.changePassword(
                    userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                    newHash: fixture.replacementHash, keepingSessionID: fixture.presenting.id, at: now))
            #expect(try await store.user(id: fixture.user.id)?.passwordHash == fixture.replacementHash)
            #expect(try await store.session(tokenHash: fixture.presenting.tokenHash) != nil)
            #expect(try await store.session(tokenHash: fixture.other.tokenHash) == nil)
            #expect(try await store.session(tokenHash: unrelatedSession.tokenHash) != nil)

            let afterChange = try Data(contentsOf: fixture.registry)
            #expect(
                try await !store.changePassword(
                    userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                    newHash: fixture.user.passwordHash, keepingSessionID: fixture.presenting.id, at: Date()))
            let staleSession = sessionFor(fixture.user)
            #expect(
                try await !store.createSession(staleSession, verifiedPasswordHash: fixture.user.passwordHash))
            #expect(try Data(contentsOf: fixture.registry) == afterChange)
            #expect(try await store.session(tokenHash: staleSession.tokenHash) == nil)

            let freshSession = sessionFor(fixture.user)
            #expect(
                try await store.createSession(freshSession, verifiedPasswordHash: fixture.replacementHash))
            #expect(try await store.session(tokenHash: freshSession.tokenHash) != nil)
        }
    }

    @Test func passwordChangeRequiresThePresentingSessionToRemainLiveAndOwned() async throws {
        try await withPasswordFixture { fixture in
            let revoked = sessionFor(fixture.user, revokedAt: Date())
            let expired = sessionFor(fixture.user, expiresAt: Date().addingTimeInterval(-1))
            let now = Date()
            let unrelated = UserRecord(
                id: AccountIdentifiers.userID(), email: "different@example.com", name: "Different",
                passwordHash: fixture.user.passwordHash, createdAt: now, passwordUpdatedAt: now)
            let foreign = sessionFor(unrelated)
            try await fixture.store.createUser(unrelated)
            for session in [revoked, expired, foreign] { try await fixture.store.createSession(session) }
            let before = try Data(contentsOf: fixture.registry)
            for sessionID in [revoked.id, expired.id, foreign.id, UUID()] {
                #expect(
                    try await !fixture.store.changePassword(
                        userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                        newHash: fixture.replacementHash, keepingSessionID: sessionID, at: Date()))
                #expect(try Data(contentsOf: fixture.registry) == before)
            }
        }
    }

    @Test func concurrentPasswordChangesHaveExactlyOneWinner() async throws {
        try await withPasswordFixture { fixture in
            let secondHash = try Bcrypt.hash("another-replacement-password", cost: 4)
            let changes = [(fixture.presenting, fixture.replacementHash), (fixture.other, secondHash)]
            let results = try await withThrowingTaskGroup(of: (Bool, SessionRecord, String).self) { group in
                for (session, hash) in changes {
                    group.addTask {
                        let changed = try await fixture.store.changePassword(
                            userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                            newHash: hash, keepingSessionID: session.id, at: Date())
                        return (changed, session, hash)
                    }
                }
                var results: [(Bool, SessionRecord, String)] = []
                for try await result in group { results.append(result) }
                return results
            }
            #expect(results.filter { $0.0 }.count == 1)
            let winner = try #require(results.first { $0.0 })
            let loser = try #require(results.first { !$0.0 })
            #expect(try await fixture.store.user(id: fixture.user.id)?.passwordHash == winner.2)
            #expect(try await fixture.store.session(tokenHash: winner.1.tokenHash) != nil)
            #expect(try await fixture.store.session(tokenHash: loser.1.tokenHash) == nil)
        }
    }

    @Test func sessionsRacingPasswordChangeCannotSurviveWithTheOldPassword() async throws {
        try await withPasswordFixture { fixture in
            let candidates = (0..<8).map { _ in sessionFor(fixture.user) }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { () async throws -> Void in
                    #expect(
                        try await fixture.store.changePassword(
                            userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                            newHash: fixture.replacementHash, keepingSessionID: fixture.presenting.id,
                            at: Date()))
                }
                for candidate in candidates {
                    group.addTask {
                        _ = try await fixture.store.createSession(
                            candidate, verifiedPasswordHash: fixture.user.passwordHash)
                    }
                }
                try await group.waitForAll()
            }
            for candidate in candidates {
                #expect(try await fixture.store.session(tokenHash: candidate.tokenHash) == nil)
            }
            #expect(try await fixture.store.session(tokenHash: fixture.presenting.tokenHash) != nil)
        }
    }

    @Test func loginRejectsPasswordReplacedAfterBcryptVerification() async throws {
        try await withPasswordFixture { fixture in
            let accounts = InterleavingAccountStore(
                base: fixture.store,
                beforeIssuing: { () async throws -> Void in
                    #expect(
                        try await fixture.store.changePassword(
                            userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                            newHash: fixture.replacementHash, keepingSessionID: fixture.presenting.id,
                            at: Date()))
                })
            let configuration = try ServerConfiguration(environment: [:])
            try await withApp(configure: { app in
                configure(
                    app, configuration: configuration, store: fixture.store, accounts: accounts,
                    passwordCost: 4)
            }) { app in
                try await app.testing().test(
                    .POST, "v1/auth/login",
                    beforeRequest: { request in
                        try request.content.encode(
                            ["email": fixture.user.email, "password": atomicityPassword], as: .json)
                    },
                    afterResponse: { response async throws in
                        #expect(response.status == .unauthorized)
                        #expect(
                            try response.content.decode(ErrorResponse.self).reason
                                == "Email or password is incorrect.")
                    })
                let document = try JSONDecoder().decode(
                    AccountsDocument.self, from: Data(contentsOf: fixture.registry))
                #expect(
                    document.sessions.filter { $0.isLive(at: Date()) }.map(\.id) == [fixture.presenting.id])
            }
        }
    }

    @Test func passwordRouteRejectsVerificationInvalidatedByAnotherPasswordChange() async throws {
        try await withPasswordFixture { fixture in
            let token = SessionToken.generate()
            let now = Date()
            let requestSession = SessionRecord(
                id: UUID(), tokenHash: SessionToken.hash(token), userID: fixture.user.id, label: "request",
                createdAt: now, lastUsedAt: now, expiresAt: now.addingTimeInterval(3600), revokedAt: nil)
            try await fixture.store.createSession(requestSession)
            let accounts = InterleavingAccountStore(
                base: fixture.store,
                beforeChanging: { () async throws -> Void in
                    #expect(
                        try await fixture.store.changePassword(
                            userID: fixture.user.id, verifiedPasswordHash: fixture.user.passwordHash,
                            newHash: fixture.replacementHash, keepingSessionID: fixture.other.id, at: Date()))
                })
            let configuration = try ServerConfiguration(environment: [:])
            try await withApp(configure: { app in
                configure(
                    app, configuration: configuration, store: fixture.store, accounts: accounts,
                    passwordCost: 4)
            }) { app in
                try await app.testing().test(
                    .PUT, "v1/auth/password", headers: ["Authorization": "Bearer \(token)"],
                    beforeRequest: { request in
                        try request.content.encode(
                            [
                                "currentPassword": atomicityPassword,
                                "newPassword": "losing-replacement-password",
                            ], as: .json)
                    },
                    afterResponse: { response async throws in
                        #expect(response.status == .unauthorized)
                        #expect(
                            try response.content.decode(ErrorResponse.self).reason
                                == "Current password is incorrect.")
                    })
                #expect(
                    try await fixture.store.user(id: fixture.user.id)?.passwordHash == fixture.replacementHash
                )
                #expect(try await fixture.store.session(tokenHash: requestSession.tokenHash) == nil)
                #expect(try await fixture.store.session(tokenHash: fixture.other.tokenHash) != nil)
            }
        }
    }
}

/// Inject a completed competing write after HTTP verification but before the route's persistence call.
/// Cover legacy methods as well, so these tests fail against the earlier unguarded route implementation.
private struct InterleavingAccountStore: AccountStore {
    let base: LocalFileStore
    var beforeIssuing: (@Sendable () async throws -> Void)? = nil
    var beforeChanging: (@Sendable () async throws -> Void)? = nil

    func createUser(_ user: UserRecord) async throws { try await base.createUser(user) }
    func user(email: String) async throws -> UserRecord? { try await base.user(email: email) }
    func user(id: String) async throws -> UserRecord? { try await base.user(id: id) }
    func updatePassword(userID: String, hash: String, at: Date) async throws {
        try await beforeChanging?()
        try await base.updatePassword(userID: userID, hash: hash, at: at)
    }
    func changePassword(
        userID: String, verifiedPasswordHash: String, newHash: String, keepingSessionID: UUID, at: Date
    ) async throws -> Bool {
        try await beforeChanging?()
        return try await base.changePassword(
            userID: userID, verifiedPasswordHash: verifiedPasswordHash, newHash: newHash,
            keepingSessionID: keepingSessionID, at: at)
    }
    func deleteUser(id: String) async throws { try await base.deleteUser(id: id) }
    func createSession(_ session: SessionRecord) async throws {
        try await beforeIssuing?()
        try await base.createSession(session)
    }
    func createSession(_ session: SessionRecord, verifiedPasswordHash: String) async throws -> Bool {
        try await beforeIssuing?()
        return try await base.createSession(session, verifiedPasswordHash: verifiedPasswordHash)
    }
    func session(tokenHash: String) async throws -> (SessionRecord, UserRecord)? {
        try await base.session(tokenHash: tokenHash)
    }
    func touchSession(id: UUID, at: Date) async throws { try await base.touchSession(id: id, at: at) }
    func revokeSession(id: UUID) async throws { try await base.revokeSession(id: id) }
    func revokeSessions(userID: String, except: UUID?) async throws {
        try await base.revokeSessions(userID: userID, except: except)
    }
}
