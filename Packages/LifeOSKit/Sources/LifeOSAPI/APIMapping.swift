import Foundation

// Wire formats and error mapping for `LifeOSAPIClient`.
extension LifeOSAPIClient {
    /// Must match the proxy's `clientDataForRequest`: `METHOD\npath\ntimestamp\nsha256hex(body)`.
    static func clientData(method: String, path: String, timestamp: String, body: Data) -> Data {
        Data("\(method.uppercased())\n\(path)\n\(timestamp)\n\(Digest.sha256Hex(body))".utf8)
    }

    // MARK: - Mapping

    struct ErrorBody: Decodable {
        let error: String?
        let message: String?
        let retryAfter: TimeInterval?
    }

    static func check(_ response: HTTPURLResponse, _ data: Data) throws {
        let status = response.statusCode
        guard !(200..<300).contains(status) else { return }
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let reason = body?.error ?? ""
        let retryAfter = body?.retryAfter
            ?? response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
        switch status {
        case 401:
            if reason == "attestation_failed" || reason == "bad_challenge" {
                throw LifeOSAPIError.attestationFailed(body?.message ?? reason)
            }
            throw LifeOSAPIError.unauthorized
        case 429:
            throw reason == "daily_quota" ? LifeOSAPIError.quotaExceeded(retryAfter: retryAfter)
                                          : LifeOSAPIError.rateLimited(retryAfter: retryAfter)
        case 503:
            throw reason == "disabled" ? LifeOSAPIError.disabled : LifeOSAPIError.serviceBusy(retryAfter: retryAfter)
        case 400, 409, 413:
            throw LifeOSAPIError.badRequest(body?.message ?? "HTTP \(status)")
        case 404:
            throw LifeOSAPIError.notFound
        case 502 where reason == "no_model_available":
            throw LifeOSAPIError.noModelAvailable
        default:
            throw LifeOSAPIError.server(status)
        }
    }

    static func map(_ error: Error) -> LifeOSAPIError {
        if let error = error as? LifeOSAPIError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            return error.code == .cancelled ? .cancelled : .network(error.localizedDescription)
        }
        return .network(String(describing: error))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LifeOSAPIError.invalidResponse
        }
    }

    static func json(_ object: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func settingStream(_ body: Data) throws -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw LifeOSAPIError.badRequest("body must be a JSON object")
        }
        object["stream"] = true
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
