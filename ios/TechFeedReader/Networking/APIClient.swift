import Foundation

enum APIError: Error, LocalizedError {
    case server(String)
    case unauthorized
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .unauthorized: return "Your session has expired. Please log in again."
        case .invalidResponse: return "The server sent back something unexpected."
        }
    }
}

/// Talks to the mobile JSON API (openspec/changes/ios-app/specs/mobile-api).
/// Auth is a bearer token from the Keychain — no cookies involved, so this
/// is fully independent of the web app's session-based auth.
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session = URLSession.shared

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private init() {
        baseURL = AppConfig.apiBaseURL
    }

    // MARK: - Auth (recovery-code login is Phase 1's native login path —
    // see design.md "Phase scoping". Sign-up hands off to the web flow
    // in a system browser sheet instead of calling an endpoint here.)

    struct RecoveryResponse: Decodable {
        let ok: Bool
        let apiToken: String?
        let recoveryCodesRemaining: Int?
    }

    func logIn(recoveryCode: String) async throws -> String {
        let body: [String: Any] = ["code": recoveryCode, "native": true]
        let response: RecoveryResponse = try await request(
            path: "/api/auth/recovery", method: "POST", jsonBody: body, authenticated: false
        )
        guard let token = response.apiToken else { throw APIError.invalidResponse }
        return token
    }

    func signOut() async throws {
        let _: EmptyResponse = try await request(path: "/api/v1/session", method: "DELETE", authenticated: true)
    }

    // MARK: - Feeds / articles / read-state

    func fetchFeeds() async throws -> [Feed] {
        try await request(path: "/api/v1/feeds", method: "GET", authenticated: true)
    }

    func fetchArticles(feedId: Int?, page: Int = 1) async throws -> [Article] {
        var path = "/api/v1/articles?page=\(page)"
        if let feedId { path += "&feed_id=\(feedId)" }
        return try await request(path: path, method: "GET", authenticated: true)
    }

    func fetchArticle(uid: String) async throws -> Article {
        try await request(path: "/api/v1/articles/\(uid)", method: "GET", authenticated: true)
    }

    struct ReadStateResponse: Decodable {
        let ok: Bool
    }

    func updateReadState(uid: String, read: Bool? = nil, bookmarked: Bool? = nil, archived: Bool? = nil) async throws {
        var body: [String: Any] = ["uid": uid]
        if let read { body["read"] = read }
        if let bookmarked { body["bookmarked"] = bookmarked }
        if let archived { body["archived"] = archived }
        let _: ReadStateResponse = try await request(path: "/api/v1/read_state", method: "POST", jsonBody: body, authenticated: true)
    }

    struct SubscribeResponse: Decodable {
        let ok: Bool
        let feed: Feed?
    }

    func subscribe(url: String) async throws -> Feed {
        let response: SubscribeResponse = try await request(
            path: "/api/v1/subscriptions", method: "POST", jsonBody: ["url": url], authenticated: true
        )
        guard let feed = response.feed else { throw APIError.invalidResponse }
        return feed
    }

    func unsubscribe(feedId: Int) async throws {
        let _: EmptyResponse = try await request(path: "/api/v1/subscriptions/\(feedId)", method: "DELETE", authenticated: true)
    }

    // MARK: - Core request plumbing

    struct EmptyResponse: Decodable { let ok: Bool? }

    private func request<T: Decodable>(
        path: String, method: String, jsonBody: [String: Any]? = nil, authenticated: Bool
    ) async throws -> T {
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        // `path` may already carry a query string (fetchArticles) — split it off
        // so URLComponents doesn't double-encode the "?".
        if let qIndex = path.firstIndex(of: "?") {
            urlComponents.path = String(path[path.startIndex..<qIndex])
            urlComponents.query = String(path[path.index(after: qIndex)...])
        } else {
            urlComponents.path = path
        }

        var req = URLRequest(url: urlComponents.url!)
        req.httpMethod = method

        if authenticated {
            guard let token = KeychainStore.loadToken() else { throw APIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.message ?? "Request failed (\(http.statusCode))."
            throw APIError.server(message)
        }
        if data.isEmpty {
            // DELETE endpoints may return an empty body — synthesize {ok:true}.
            let empty = try encoder.encode(["ok": true])
            return try decoder.decode(T.self, from: empty)
        }
        return try decoder.decode(T.self, from: data)
    }

    private struct ErrorBody: Decodable { let message: String? }
}
