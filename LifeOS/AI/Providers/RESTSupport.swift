import Foundation

/// Shared HTTP behaviour for BYOK REST providers, generalised from
/// `GroqMealAnalyzer`: one retry with backoff for 429/5xx/transport blips,
/// precise status → `AIError` mapping, cancellation honoured end to end.
nonisolated struct RESTTransport: Sendable {
    let session: URLSession
    let provider: ProviderID
    var maxAttempts = 2
    /// Injected for tests so retries don't actually sleep.
    var backoff: @Sendable (Int) async throws -> Void = { attempt in
        try await Task.sleep(for: .milliseconds(attempt == 1 ? 600 : 1_400))
    }

    static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    /// Sends the request and returns the body of a 2xx response.
    /// - Parameter classify: maps a non-2xx status + body to an error; return nil
    ///   to use the default mapping.
    func send(_ request: URLRequest,
              classify: @Sendable (Int, Data) -> AIError? = { _, _ in nil }) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw AIError.invalidOutput("no HTTP response") }
                if (200..<300).contains(http.statusCode) { return data }

                let error = classify(http.statusCode, data) ?? Self.defaultError(for: http.statusCode, provider: provider)
                let retryable: Bool
                switch error {
                case .rateLimited, .server: retryable = true
                default: retryable = false
                }
                if retryable, attempt < maxAttempts {
                    try await backoff(attempt)
                    continue
                }
                throw error
            } catch let error as AIError {
                throw error
            } catch is CancellationError {
                throw AIError.cancelled
            } catch let error as URLError where error.code == .cancelled {
                throw AIError.cancelled
            } catch {
                if attempt < maxAttempts, !Task.isCancelled {
                    try await backoff(attempt)
                    continue
                }
                throw AIError.from(error)
            }
        }
    }

    static func defaultError(for status: Int, provider: ProviderID) -> AIError {
        switch status {
        case 401, 403: .authFailed(provider)
        case 429: .rateLimited(provider)
        // Almost always a decommissioned/unknown model for this key (legacy rule).
        case 400, 404, 422: .noModelAvailable
        case 500..<600: .server(status)
        default: .server(status)
        }
    }
}

/// Builds `[String: Any]` JSON bodies from `JSONValue` (ordered, Sendable).
nonisolated enum RESTBody {
    static func data(_ value: JSONValue) -> Data { Data(value.serialized().utf8) }
}

/// Whether text contains a parseable JSON object — used to skip a model that
/// answered in prose (legacy `badResponse` → next model).
nonisolated func containsJSONObject(_ text: String) -> Bool {
    guard case .object? = JSONValue.parse(SchemaValidator.isolateJSONObject(text)) else { return false }
    return true
}
