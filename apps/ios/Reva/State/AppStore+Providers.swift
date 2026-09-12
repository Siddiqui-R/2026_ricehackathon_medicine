// Purpose: Construct the provider client and discover configured capabilities.
// Inputs: The in-memory server URL/token.
// Outputs: ProviderClient or published service capability information.
// Side effects: GET service configuration; saves only the server URL to user defaults.

// MARK: - Configured client creation
// Reuse the shared transport validation for URL and token handling.
import Foundation

extension AppStore {
    // MARK: - Provider publication context
    // Connection switches and workspace replacement invalidate results, while unrelated edits remain allowed.
    struct ProviderContext: Equatable {
        let connection: UUID
        let workspace: UUID
    }

    var providerContext: ProviderContext {
        ProviderContext(connection: connectionGeneration, workspace: workspaceGeneration)
    }

    func providerClient() throws -> ProviderClient {
        try ProviderClient(url: connectionURL, token: connectionToken)
    }
    // MARK: - Service discovery
    // Read configuration flags and models; this operation does not test provider credentials.
    func checkProviders() async {
        let requestID = UUID()
        providerDiscoveryID = requestID
        let context = providerContext
        let url = connectionURL
        let token = connectionToken
        do {
            let status = try await ProviderClient(url: url, token: token).status()
            guard context == providerContext, requestID == providerDiscoveryID else { return }
            try Task.checkCancellation()
            providerStatus = status
            UserDefaults.standard.set(url, forKey: "serverURL")
            notice = "Service configuration checked. Only configured connections can be used."
        } catch {
            guard context == providerContext, requestID == providerDiscoveryID else { return }
            providerStatus = nil
            errorMessage = error.localizedDescription
        }
    }
}
