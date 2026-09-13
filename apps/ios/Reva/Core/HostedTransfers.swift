// Match the hosted web API's chunked originals without exceeding its request/response size limits.
import Foundation

enum HostedTransfers {
    static let chunkSize = 3 * 1024 * 1024
    static let maximum = 16 * 1024 * 1024
    static func enabled(_ origin: URL) -> Bool {
        origin.scheme == "https"
            && ["revamed.health", "www.revamed.health"].contains(origin.host?.lowercased() ?? "")
    }
    private static func send(_ request: URLRequest, session: URLSession) async throws -> (
        Data, HTTPURLResponse
    ) {
        try Task.checkCancellation()
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse else {
            throw RevaError.invalid("The file transfer response was unreadable.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ServerFailure.response(response.statusCode)
        }
        return (data, response)
    }
    static func stage(_ data: Data, origin: URL, token: String, session: URLSession) async throws -> String? {
        guard enabled(origin), data.count > chunkSize else { return nil }
        guard data.count <= maximum else {
            throw RevaError.invalid("Original files must be no larger than 16 MiB.")
        }
        let id = UUID().uuidString.lowercased()
        for offset in stride(from: 0, to: data.count, by: chunkSize) {
            var url = URLComponents(
                url: origin.appendingPathComponent("v1/transfers/" + id), resolvingAgainstBaseURL: false)!
            url.queryItems = [
                .init(name: "offset", value: String(offset)), .init(name: "total", value: String(data.count)),
            ]
            var request = URLRequest(url: url.url!)
            request.httpMethod = "PUT"
            request.httpBody = data.subdata(in: offset..<min(offset + chunkSize, data.count))
            request.timeoutInterval = 25
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            _ = try await send(request, session: session)
        }
        return id
    }
    static func download(id: String, origin: URL, token: String, session: URLSession) async throws -> Data {
        var result = Data()
        var total = 0
        var etag = ""
        repeat {
            var request = URLRequest(url: origin.appendingPathComponent("v1/attachments/" + id))
            request.timeoutInterval = 25
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(
                "bytes=\(result.count)-\(result.count + chunkSize - 1)", forHTTPHeaderField: "Range")
            if !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-Match") }
            let (chunk, response) = try await send(request, session: session)
            let header = response.value(forHTTPHeaderField: "Content-Range") ?? ""
            let numbers = header.dropFirst(6).split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap {
                Int($0)
            }
            guard response.statusCode == 206,
                header.range(of: #"^bytes [0-9]+-[0-9]+/[0-9]+$"#, options: .regularExpression) != nil,
                numbers.count == 3,
                numbers[0] == result.count, numbers[1] >= numbers[0],
                numbers[2] > numbers[1], numbers[2] <= maximum,
                numbers[1] - numbers[0] + 1 == chunk.count,
                !chunk.isEmpty, chunk.count <= chunkSize,
                total == 0 || total == numbers[2],
                let nextTag = response.value(forHTTPHeaderField: "ETag"), !nextTag.isEmpty,
                etag.isEmpty || etag == nextTag
            else {
                throw RevaError.invalid(
                    "The original changed during download or returned an invalid range. Please retry.")
            }
            total = numbers[2]
            etag = nextTag
            result.append(chunk)
        } while result.count < total
        return result
    }
}
