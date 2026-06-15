import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest<Response: Decodable> {
    let url: URL
    var method: HTTPMethod
    var headers: [String: String]
    var body: Data?
    var decoder: JSONDecoder

    init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.decoder = decoder
    }
}

protocol APIClient {
    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response
}

enum APIClientError: Error {
    case invalidResponse
    case badStatus(Int)
    case emptyBody
}

final class URLSessionAPIClient: APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.allHTTPHeaderFields = request.headers
        urlRequest.httpBody = request.body

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIClientError.badStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw APIClientError.emptyBody
        }

        return try request.decoder.decode(Response.self, from: data)
    }
}
