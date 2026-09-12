// Purpose: Resolve listener, owner identity, account, CORS, storage, and provider settings before starting services.
// Inputs: An explicit environment dictionary and optional supported command arguments.
// Outputs: Immutable validated configuration or a descriptive ConfigurationError.
// Side effects: None here. Constructing database/provider configuration does not open a connection.
// Ownership: The public demo identity is restricted to loopback local storage. Other modes need private tokens or accounts.

import Foundation
import PostgresNIO

// MARK: - Immutable configuration contract
public struct ServerConfiguration: Sendable {
    public static let demoToken = "reva-local-demo-token"
    public let mode: String
    public let hostname: String
    public let port: Int
    public let directory: URL
    public let tokens: [String: String]
    public let isDemo: Bool
    public let postgres: PostgresClient.Configuration?
    public let providers: ProviderConfiguration
    public let accountsEnabled: Bool
    public let signupOpen: Bool
    public let sessionDays: Int
    public let allowedOrigins: [String]

    // MARK: - Validate arguments and listener settings
    public init(
        environment env: [String: String] = ProcessInfo.processInfo.environment, arguments: [String] = []
    ) throws {
        guard arguments.isEmpty || [["serve"], ["routes"], ["--help"], ["help"]].contains(arguments) else {
            throw ConfigurationError(
                "Use REVA_HOST and REVA_PORT for the listener. Only serve, routes, and help commands are supported; CLI binding overrides are disabled."
            )
        }
        mode = env["REVA_STORAGE"] ?? "local"
        guard ["local", "postgres"].contains(mode) else {
            throw ConfigurationError("REVA_STORAGE must be local or postgres.")
        }
        hostname = env["REVA_HOST"] ?? "127.0.0.1"
        guard !hostname.isEmpty else { throw ConfigurationError("REVA_HOST cannot be empty.") }
        guard let parsedPort = Int(env["REVA_PORT"] ?? "8080"), (1...65535).contains(parsedPort) else {
            throw ConfigurationError("REVA_PORT must be between 1 and 65535.")
        }
        port = parsedPort
        directory = URL(fileURLWithPath: env["REVA_DATA_DIRECTORY"] ?? ".local-data", isDirectory: true)
        // MARK: - Account, sign-up, session lifetime, and CORS settings
        let accountsSetting = env["REVA_ACCOUNTS"] ?? "enabled"
        guard ["enabled", "disabled"].contains(accountsSetting) else {
            throw ConfigurationError("REVA_ACCOUNTS must be enabled or disabled.")
        }
        accountsEnabled = accountsSetting == "enabled"
        let signupSetting = env["REVA_SIGNUP"] ?? "open"
        guard ["open", "closed"].contains(signupSetting) else {
            throw ConfigurationError("REVA_SIGNUP must be open or closed.")
        }
        signupOpen = signupSetting == "open"
        guard let days = Int(env["REVA_SESSION_DAYS"] ?? "30"), (1...365).contains(days) else {
            throw ConfigurationError("REVA_SESSION_DAYS must be between 1 and 365.")
        }
        sessionDays = days
        allowedOrigins = try Self.parseOrigins(env["REVA_ALLOWED_ORIGINS"])
        // MARK: - Resolve private owners, account-only identity, or the restricted local demo identity
        if let raw = env["REVA_TOKENS"] {
            guard let data = raw.data(using: .utf8),
                let configured = try? JSONDecoder().decode([String: String].self, from: data),
                !configured.isEmpty, configured.count <= 100,
                configured.allSatisfy({ key, value in
                    key.utf8.count >= 24 && key.utf8.count <= 256 && key != Self.demoToken
                        && key.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) && Validation.safeID(value)
                })
            else {
                throw ConfigurationError(
                    "REVA_TOKENS must be a nonempty JSON token-to-owner object; tokens need 24–256 visible ASCII characters and owner IDs must be safe IDs."
                )
            }
            tokens = configured
            isDemo = false
        } else if mode == "local", Self.isLoopback(hostname) {
            // The public demo token exists only here; account sign-up also works in this mode.
            tokens = [Self.demoToken: "demo-user"]
            isDemo = true
        } else if accountsEnabled {
            tokens = [:]
            isDemo = false
        } else {
            throw ConfigurationError(
                "PostgreSQL or a non-loopback listener requires REVA_TOKENS or REVA_ACCOUNTS=enabled.")
        }
        // MARK: - Provider authorization and database transport policy
        providers = try ProviderConfiguration(environment: env, paidAccessAllowed: !isDemo)
        if mode == "postgres" {
            guard let raw = env["DATABASE_URL"], let url = URLComponents(string: raw),
                ["postgres", "postgresql"].contains(url.scheme ?? ""),
                let host = url.host, !host.isEmpty,
                let user = url.user, !user.isEmpty,
                let password = url.password, !password.isEmpty,
                url.path.count > 1, !url.path.dropFirst().contains("/"),
                url.fragment == nil,
                (1...65535).contains(url.port ?? 5432)
            else {
                throw ConfigurationError(
                    "PostgreSQL requires DATABASE_URL with postgres scheme, host, user, password, database, and valid port."
                )
            }
            let items = url.queryItems ?? []
            guard items.allSatisfy({ $0.name == "sslmode" }), items.count <= 1 else {
                throw ConfigurationError(
                    "DATABASE_URL only supports the sslmode query option; remove unsupported options.")
            }
            let tlsMode = items.first?.value ?? "verify-full"
            let tls: PostgresClient.Configuration.TLS
            switch tlsMode {
            case "verify-full", "require": tls = .require(.makeClientConfiguration())
            case "disable" where Self.isLoopback(host) && env["REVA_ALLOW_INSECURE_LOCAL_POSTGRES"] == "true":
                tls = .disable
            default:
                throw ConfigurationError(
                    "Use sslmode=verify-full; disabling TLS requires loopback and REVA_ALLOW_INSECURE_LOCAL_POSTGRES=true."
                )
            }
            var databaseConfiguration = PostgresClient.Configuration(
                host: host, port: url.port ?? 5432, username: user, password: password,
                database: String(url.path.dropFirst()), tls: tls)
            databaseConfiguration.options.connectTimeout = .seconds(5)
            databaseConfiguration.options.maximumConnections = 4
            databaseConfiguration.options.additionalStartupParameters = [
                ("statement_timeout", "15000"), ("application_name", "reva-prototype"),
            ]
            postgres = databaseConfiguration
        } else {
            guard env["DATABASE_URL"] == nil else {
                throw ConfigurationError(
                    "DATABASE_URL was provided while REVA_STORAGE is local. Select postgres explicitly or remove DATABASE_URL."
                )
            }
            postgres = nil
        }
    }

    // MARK: - Local-only hostname policy
    private static func isLoopback(_ host: String) -> Bool {
        ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
    }

    // MARK: - Exact CORS origins: https anywhere, http only on loopback, never a wildcard
    /// Each entry must be canonical (lowercase scheme/host, no path, query, fragment, userinfo, or trailing slash)
    /// so it compares equal to the Origin header a browser sends.
    static func parseOrigins(_ raw: String?) throws -> [String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var origins: [String] = []
        for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let entry = piece.trimmingCharacters(in: .whitespaces)
            guard isValidOrigin(entry) else {
                throw ConfigurationError(
                    "REVA_ALLOWED_ORIGINS entries must be exact https://host[:port] origins or http://127.0.0.1|localhost[:port]; wildcards are not allowed."
                )
            }
            if !origins.contains(entry) { origins.append(entry) }
        }
        guard origins.count <= 50 else {
            throw ConfigurationError("REVA_ALLOWED_ORIGINS allows at most 50 origins.")
        }
        return origins
    }

    private static func isValidOrigin(_ entry: String) -> Bool {
        guard !entry.isEmpty, entry.utf8.count <= 260, entry.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
            let components = URLComponents(string: entry), let scheme = components.scheme,
            let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
            components.path.isEmpty, components.query == nil, components.fragment == nil,
            (1...65535).contains(components.port ?? 443)
        else { return false }
        let canonical = scheme + "://" + host + (components.port.map { ":\($0)" } ?? "")
        guard canonical == entry, scheme == scheme.lowercased(), host == host.lowercased() else {
            return false
        }
        switch scheme {
        case "https": return true
        case "http": return ["127.0.0.1", "localhost"].contains(host)
        default: return false
        }
    }
}

// MARK: - Safe configuration failures for the entry point
public struct ConfigurationError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ description: String) { self.description = description }
}
