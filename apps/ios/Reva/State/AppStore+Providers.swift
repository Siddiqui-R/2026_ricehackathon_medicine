// Purpose: Construct the provider client and discover configured capabilities.
// Inputs: The in-memory server URL/token.
// Outputs: ProviderClient or published service capability information.
// Side effects: GET service configuration; saves only the server URL to user defaults.

import Foundation

// MARK: - Configured client creation
// Reuse the shared transport validation for URL and token handling.

extension AppStore {
    func providerClient() throws -> ProviderClient {
        try ProviderClient(url: connectionURL, token: connectionToken)
    }
    // MARK: - Provider result ownership
    // Ordinary edits use each operation's source checks; identity switches and pulls/reset invalidate all results.
    func providerContext() -> ProviderContext {
        ProviderContext(connection: connectionGeneration, workspace: workspaceGeneration)
    }
    func isCurrent(_ context: ProviderContext) -> Bool {
        context.connection == connectionGeneration && context.workspace == workspaceGeneration
    }
    // MARK: - Service discovery
    // Read configuration flags and models; this operation does not test provider credentials.
    func checkProviders() async {
        let requestID = UUID()
        providerDiscoveryID = requestID
        let context = providerContext()
        let url = connectionURL
        let token = connectionToken
        do {
            let status = try await ProviderClient(url: url, token: token).status()
            guard isCurrent(context), requestID == providerDiscoveryID else { return }
            try Task.checkCancellation()
            providerStatus = status
            UserDefaults.standard.set(url, forKey: "serverURL")
            notice = "Service configuration checked. Only configured connections can be used."
        } catch {
            guard isCurrent(context), requestID == providerDiscoveryID else { return }
            providerStatus = nil
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Captured operation boundary
// UUID generations detect switching away and back even when IDs and source text are identical.
struct ProviderContext {
    let connection: UUID
    let workspace: UUID
}
