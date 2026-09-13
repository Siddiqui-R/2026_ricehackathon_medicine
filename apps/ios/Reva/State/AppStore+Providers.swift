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

    // Retain request cancellation independently of the view task that initiated it.
    // A workspace/connection switch stops both URLSession requests and Gemini backoff immediately.
    func withProviderRequest<T>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let id = UUID()
        let request = Task { @MainActor in
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        providerRequestCancellations[id] = { request.cancel() }
        defer { providerRequestCancellations.removeValue(forKey: id) }
        return try await withTaskCancellationHandler {
            try await request.value
        } onCancel: {
            request.cancel()
        }
    }

    func cancelProviderRequests() {
        let cancellations = Array(providerRequestCancellations.values)
        providerRequestCancellations.removeAll()
        for cancel in cancellations { cancel() }
    }

    func providerClient() throws -> ProviderClient {
        try ProviderClient(
            url: connectionURL, token: connectionToken,
            session: account == nil ? .shared : NativeAccountTransport.session)
    }
    // MARK: - Service discovery
    // Read configuration flags and models; this operation does not test provider credentials.
    func checkProviders() async {
        let requestID = UUID()
        providerDiscoveryID = requestID
        let context = providerContext
        let url = connectionURL
        do {
            let status = try await withProviderRequest { try await self.providerClient().status() }
            guard context == providerContext, requestID == providerDiscoveryID else { return }
            try Task.checkCancellation()
            providerStatus = status
            if account == nil { UserDefaults.standard.set(url, forKey: "serverURL") }
            notice = "Service configuration checked. Only configured connections can be used."
        } catch {
            guard context == providerContext, requestID == providerDiscoveryID else { return }
            providerStatus = nil
            errorMessage = error.localizedDescription
        }
    }
}
