// Purpose: Isolate Gemini HTTP I/O behind an injectable fixed-host transport.
// Inputs: One HTTPS request to generativelanguage.googleapis.com, or a replacement transport in tests.
// Outputs: Status/body bytes or a transport failure with bounded request/resource timeouts.
// Side effects: Creates an ephemeral URLSession, sends one request without redirects, then invalidates it.
// Bounds: Apple platforms stop streaming at 1 MiB. FoundationNetworking checks the limit after collection.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Injectable status-and-bytes contract
struct GeminiHTTPResponse: Sendable {
    let status: Int
    let data: Data
}

/// Injected by mocked tests. Live requests use only the fixed Google host and never follow redirects.
public struct GeminiHTTPTransport: Sendable {
    let send: @Sendable (URLRequest) async throws -> GeminiHTTPResponse

    // MARK: - Ephemeral fixed-host request with bounded response collection
    static var live: Self {
        Self { request in
            guard request.url?.scheme == "https", request.url?.host == "generativelanguage.googleapis.com"
            else {
                throw GeminiTransportFailure()
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 35
            configuration.timeoutIntervalForResource = 35
            let session = URLSession(
                configuration: configuration, delegate: GeminiNoRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            #if canImport(FoundationNetworking)
                let (data, response) = try await session.data(for: request)
                guard data.count <= 1_048_576 else { throw GeminiResponseTooLarge() }
            #else
                let (bytes, response) = try await session.bytes(for: request)
                guard response.expectedContentLength <= 1_048_576 else { throw GeminiResponseTooLarge() }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 1_048_576 else { throw GeminiResponseTooLarge() }
                    data.append(byte)
                }
            #endif
            guard let response = response as? HTTPURLResponse else { throw GeminiTransportFailure() }
            return GeminiHTTPResponse(status: response.statusCode, data: data)
        }
    }
}

// MARK: - Prevent redirect-based credential forwarding
private final class GeminiNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct GeminiTransportFailure: Error {}

struct GeminiResponseTooLarge: Error {}
