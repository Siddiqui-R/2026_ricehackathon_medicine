import RevaServer
import Vapor
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum EntryPoint {
    static func main() async {
        do { try await run() }
        catch {
            let reason: String
            if let configuration = error as? ConfigurationError { reason = configuration.description }
            else if let database = error as? ConfigurationErrorForStartup { reason = database.description }
            else { reason = "Server startup/runtime failed. Check listener and storage permissions; sensitive details suppressed." }
            try? FileHandle.standardError.write(contentsOf: Data(("Reva: " + reason + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let configuration = try ServerConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
        let app = try await Application.make(.detect())
        var postgresTask: Task<Void, Never>?
        do {
            let store: any RevaStore
            if let database = configuration.postgres {
                let postgres = PostgresStore(configuration: database)
                postgresTask = Task { await postgres.client.run() }
                do { try await withDatabaseDeadline { try await postgres.migrate() } }
                catch { throw ConfigurationErrorForStartup() }
                store = BoundedStore(base: postgres)
            } else {
                store = try LocalFileStore(directory: configuration.directory)
            }
            configure(app, configuration: configuration, store: store)
            app.logger.notice("Reva storage=\(configuration.mode), demo=\(configuration.isDemo). Local mode is for fictional development data only.")
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

private struct ConfigurationErrorForStartup: Error, CustomStringConvertible {
    var description: String { "PostgreSQL startup/migration failed. Verify DATABASE_URL, TLS trust and database permissions. No local fallback was used; sensitive database details suppressed." }
}
