// Purpose: Assemble one configured server and own its database/background-task lifetime.
// Inputs: Process environment and the restricted server command arguments.
// Outputs: A running HTTP service, or a nonzero exit with a sanitized startup/runtime reason.
// Side effects: Opens storage/listener resources, applies database migrations, and shuts them down on exit.
// Failure boundary: PostgreSQL startup failure never switches to local storage or prints raw credentials.

import RevaServer
import Vapor

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// MARK: - Process entry and sanitized failure reporting
@main
enum EntryPoint {
    static func main() async {
        do { try await run() } catch {
            let reason: String
            if let configuration = error as? ConfigurationError {
                reason = configuration.description
            } else if let database = error as? ConfigurationErrorForStartup {
                reason = database.description
            } else {
                reason =
                    "Server startup/runtime failed. Check listener and storage permissions; sensitive details suppressed."
            }
            try? FileHandle.standardError.write(contentsOf: Data(("Reva: " + reason + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    // MARK: - Service assembly and symmetric shutdown
    // The database runner must live as long as the app and be cancelled on both success and failure.
    private static func run() async throws {
        let configuration = try ServerConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
        let app = try await Application.make(.detect())
        var postgresTask: Task<Void, Never>?
        do {
            // MARK: - Explicit storage selection and migration gate
            // The same adapter serves owner state and accounts; accounts are passed only when enabled.
            let store: any RevaStore
            let accounts: (any AccountStore)?
            if let database = configuration.postgres {
                let postgres = PostgresStore(configuration: database)
                postgresTask = Task { await postgres.client.run() }
                do { try await withDatabaseDeadline { try await postgres.migrate() } } catch {
                    throw ConfigurationErrorForStartup()
                }
                store = BoundedStore(base: postgres)
                accounts = configuration.accountsEnabled ? BoundedAccountStore(base: postgres) : nil
            } else {
                let local = try LocalFileStore(directory: configuration.directory)
                store = local
                accounts = configuration.accountsEnabled ? local : nil
            }
            // MARK: - Listener lifetime after storage is ready
            configure(app, configuration: configuration, store: store, accounts: accounts)
            app.logger.notice(
                "Reva storage=\(configuration.mode), demo=\(configuration.isDemo), accounts=\(configuration.accountsEnabled), signupOpen=\(configuration.signupOpen). Local mode is for fictional development data only."
            )
            try await app.execute()
            try await app.asyncShutdown()
            postgresTask?.cancel()
            await postgresTask?.value
        } catch {
            try? await app.asyncShutdown()
            postgresTask?.cancel()
            await postgresTask?.value
            throw error
        }
    }
}

// MARK: - Credential-safe database startup error
private struct ConfigurationErrorForStartup: Error, CustomStringConvertible {
    var description: String {
        "PostgreSQL startup/migration failed. Verify DATABASE_URL, TLS trust and database permissions. No local fallback was used; sensitive database details suppressed."
    }
}
