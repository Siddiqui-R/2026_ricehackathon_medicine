import Foundation
import PostgresNIO

public struct ServerConfiguration: Sendable {
    public static let demoToken = "reva-local-demo-token"
    public let mode: String
    public let hostname: String
    public let port: Int
    public let directory: URL
    public let tokens: [String: String]
    public let isDemo: Bool
    public let postgres: PostgresClient.Configuration?

    public init(environment env: [String: String] = ProcessInfo.processInfo.environment, arguments: [String] = []) throws {
        guard arguments.isEmpty || [["serve"], ["routes"], ["--help"], ["help"]].contains(arguments) else {
            throw ConfigurationError("Use REVA_HOST and REVA_PORT for the listener. Only serve, routes, and help commands are supported; CLI binding overrides are disabled.")
        }
        mode = env["REVA_STORAGE"] ?? "local"
        guard ["local", "postgres"].contains(mode) else { throw ConfigurationError("REVA_STORAGE must be local or postgres.") }
        hostname = env["REVA_HOST"] ?? "127.0.0.1"
        guard !hostname.isEmpty else { throw ConfigurationError("REVA_HOST cannot be empty.") }
        guard let parsedPort = Int(env["REVA_PORT"] ?? "8080"), (1...65535).contains(parsedPort) else {
            throw ConfigurationError("REVA_PORT must be between 1 and 65535.")
        }
        port = parsedPort
        directory = URL(fileURLWithPath: env["REVA_DATA_DIRECTORY"] ?? ".local-data", isDirectory: true)
        if let raw = env["REVA_TOKENS"] {
            guard let data = raw.data(using: .utf8), let configured = try? JSONDecoder().decode([String: String].self, from: data),
                  !configured.isEmpty, configured.count <= 100,
                  configured.allSatisfy({ key, value in
                      key.utf8.count >= 24 && key.utf8.count <= 256 && key != Self.demoToken &&
                      key.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) && Validation.safeID(value)
                  }) else { throw ConfigurationError("REVA_TOKENS must be a nonempty JSON token-to-owner object; tokens need 24–256 visible ASCII characters and owner IDs must be safe IDs.") }
            tokens = configured
            isDemo = false
        } else {
            guard mode == "local", Self.isLoopback(hostname) else {
                throw ConfigurationError("Explicit REVA_TOKENS is required for PostgreSQL or a non-loopback listener.")
            }
            tokens = [Self.demoToken: "demo-user"]
            isDemo = true
        }
        if mode == "postgres" {
            guard let raw = env["DATABASE_URL"], let url = URLComponents(string: raw),
                  ["postgres", "postgresql"].contains(url.scheme ?? ""),
                  let host = url.host, !host.isEmpty,
                  let user = url.user, !user.isEmpty,
                  let password = url.password, !password.isEmpty,
                  url.path.count > 1, !url.path.dropFirst().contains("/"),
                  url.fragment == nil,
                  (1...65535).contains(url.port ?? 5432) else {
                throw ConfigurationError("PostgreSQL requires DATABASE_URL with postgres scheme, host, user, password, database, and valid port.")
            }
            let items = url.queryItems ?? []
            guard items.allSatisfy({ $0.name == "sslmode" }), items.count <= 1 else {
                throw ConfigurationError("DATABASE_URL only supports the sslmode query option; remove unsupported options.")
            }
            let tlsMode = items.first?.value ?? "verify-full"
            let tls: PostgresClient.Configuration.TLS
            switch tlsMode {
            case "verify-full", "require": tls = .require(.makeClientConfiguration())
            case "disable" where Self.isLoopback(host) && env["REVA_ALLOW_INSECURE_LOCAL_POSTGRES"] == "true": tls = .disable
            default: throw ConfigurationError("Use sslmode=verify-full; disabling TLS requires loopback and REVA_ALLOW_INSECURE_LOCAL_POSTGRES=true.")
            }
            var databaseConfiguration = PostgresClient.Configuration(host: host, port: url.port ?? 5432, username: user, password: password, database: String(url.path.dropFirst()), tls: tls)
            databaseConfiguration.options.connectTimeout = .seconds(5)
            databaseConfiguration.options.maximumConnections = 4
            databaseConfiguration.options.additionalStartupParameters = [("statement_timeout", "15000"), ("application_name", "reva-prototype")]
            postgres = databaseConfiguration
        } else {
            guard env["DATABASE_URL"] == nil else {
                throw ConfigurationError("DATABASE_URL was provided while REVA_STORAGE is local. Select postgres explicitly or remove DATABASE_URL.")
            }
            postgres = nil
        }
    }

    private static func isLoopback(_ host: String) -> Bool { ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) }
}

public struct ConfigurationError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ description: String) { self.description = description }
}
