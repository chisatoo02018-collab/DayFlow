import Foundation

enum GoogleAPIError: Error {
    case requestFailed(statusCode: Int)
}

/// Thin authenticated JSON client shared by the Google Calendar and Google Tasks services.
struct GoogleAPIClient {
    let authManager: GoogleAuthManager

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func get<Response: Decodable>(_ url: URL) async throws -> Response {
        let request = try await authorizedRequest(method: "GET", url: url)
        return try await perform(request)
    }

    func patch<Body: Encodable, Response: Decodable>(_ url: URL, body: Body) async throws -> Response {
        var request = try await authorizedRequest(method: "PATCH", url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func authorizedRequest(method: String, url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await authManager.accessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GoogleAPIError.requestFailed(statusCode: statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}
