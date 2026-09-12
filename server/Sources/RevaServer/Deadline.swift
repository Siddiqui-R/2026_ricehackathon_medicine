// Purpose: Apply a shared cancellation deadline to database acquisition and store operations.
// Inputs: A Sendable asynchronous operation, or a RevaStore to wrap.
// Outputs: The operation result/error, or DatabaseDeadlineExceeded when the timer wins.
// Side effects: Starts a 20-second timer task and cancels the losing task. Underlying work must honor cancellation.

import Foundation

// MARK: - Race work against a cancellation deadline
/// PostgresClient can retry connection acquisition; bound that wait as well as SQL execution.
public func withDatabaseDeadline<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T)
    async throws -> T
{
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(20))
            throw DatabaseDeadlineExceeded()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw DatabaseDeadlineExceeded() }
        return result
    }
}

private struct DatabaseDeadlineExceeded: Error {}

// MARK: - Apply the same deadline to the complete store interface
/// Every database call, including health probes, receives a finite acquisition deadline.
public struct BoundedStore: RevaStore {
    public let base: any RevaStore
    public init(base: any RevaStore) { self.base = base }
    public func health() async throws { try await withDatabaseDeadline { try await base.health() } }
    public func getState(owner: String) async throws -> StateEnvelope {
        try await withDatabaseDeadline { try await base.getState(owner: owner) }
    }
    public func putState(owner: String, baseRevision: Int, snapshot: JSONValue) async throws -> Int {
        try await withDatabaseDeadline {
            try await base.putState(owner: owner, baseRevision: baseRevision, snapshot: snapshot)
        }
    }
    public func deleteState(owner: String) async throws -> Int {
        try await withDatabaseDeadline { try await base.deleteState(owner: owner) }
    }
    public func putAttachment(owner: String, attachment: StoredAttachment) async throws {
        try await withDatabaseDeadline { try await base.putAttachment(owner: owner, attachment: attachment) }
    }
    public func getAttachment(owner: String, id: String) async throws -> StoredAttachment {
        try await withDatabaseDeadline { try await base.getAttachment(owner: owner, id: id) }
    }
    public func deleteAttachment(owner: String, id: String) async throws {
        try await withDatabaseDeadline { try await base.deleteAttachment(owner: owner, id: id) }
    }
}
