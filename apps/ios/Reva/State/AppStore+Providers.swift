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
    // MARK: - Service discovery
    // Read configuration flags and models; this operation does not test provider credentials.
    func checkProviders() async {
        do {
            providerStatus = try await providerClient().status()
            UserDefaults.standard.set(connectionURL, forKey: "serverURL")
            notice = "Service configuration checked. Only configured connections can be used."
        } catch {
            providerStatus = nil
            errorMessage = error.localizedDescription
        }
    }
}
