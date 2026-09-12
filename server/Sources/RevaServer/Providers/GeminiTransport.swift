import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GeminiHTTPResponse: Sendable { let status: Int; let data: Data }

/// Injected by mocked tests. Live requests use only the fixed Google host and never follow redirects.
public struct GeminiHTTPTransport: Sendable {
    let send: @Sendable (URLRequest) async throws -> GeminiHTTPResponse

    static var live: Self {
        Self { request in
            guard request.url?.scheme == "https", request.url?.host == "generativelanguage.googleapis.com" else {
                throw GeminiTransportFailure()
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 40
            configuration.timeoutIntervalForResource = 45
            let session = URLSession(configuration: configuration, delegate: GeminiNoRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            #if canImport(FoundationNetworking)
            let (data, response) = try await session.data(for: request)
            guard data.count <= 1_048_576 else { throw GeminiTransportFailure() }
            #else
            let (bytes, response) = try await session.bytes(for: request)
            guard response.expectedContentLength <= 1_048_576 else { throw GeminiTransportFailure() }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw GeminiTransportFailure() }
                data.append(byte)
            }
            #endif
            guard let response = response as? HTTPURLResponse else { throw GeminiTransportFailure() }
            return GeminiHTTPResponse(status: response.statusCode, data: data)
        }
    }
}

private final class GeminiNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct GeminiTransportFailure: Error {}
