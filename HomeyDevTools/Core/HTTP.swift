import Foundation

struct APIError: LocalizedError, Sendable {
    let status: Int
    let message: String
    let url: String

    var errorDescription: String? {
        status == 0 ? message : "HTTP \(status): \(message)"
    }
    var isUnauthorized: Bool { status == 401 }
}

enum HTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    struct Response: Sendable {
        let status: Int
        let data: Data
        let headers: [String: String]
        var json: JSON { JSON.parse(data) }
    }

    @discardableResult
    static func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("HomeyDevTools-iOS/1.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = body
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError(status: 0, message: error.localizedDescription, url: url.absoluteString)
        }
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        var hdrs: [String: String] = [:]
        http?.allHeaderFields.forEach { if let k = $0.key as? String { hdrs[k] = "\($0.value)" } }
        guard (200..<300).contains(status) else {
            let j = JSON.parse(data)
            var msg = j.firstString("message", "error_description", "error")
            if msg.isEmpty { msg = String(data: data.prefix(300), encoding: .utf8) ?? L("Onbekende fout") }
            throw APIError(status: status, message: msg, url: url.absoluteString)
        }
        return Response(status: status, data: data, headers: hdrs)
    }

    static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let s = params.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
        return Data(s.utf8)
    }
}

enum JWT {
    /// Expiry (minus a 60s safety margin) of a JWT, or nil when it can't be read.
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let exp = JSON.parse(data)["exp"].double else { return nil }
        return Date(timeIntervalSince1970: exp - 60)
    }
}
