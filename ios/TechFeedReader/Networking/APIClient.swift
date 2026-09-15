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

/// Talks to the mobile JSON API (openspec/changes/ios-app/specs/mobile-api,
/// specs/mobile-reading-parity). Auth is a bearer token from the Keychain —
/// no cookies involved, so this is fully independent of the web app's
/// session-based auth.
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

    /// `state`: "unread" | "bookmarked" | "archived" | "all" (server default) — see mobile-reading-parity spec.
    func fetchArticles(feedId: Int? = nil, tagId: Int? = nil, state: String? = nil, topic: String? = nil, page: Int = 1) async throws -> [Article] {
        let path = urlPath("/api/v1/articles", query: [
            "page": String(page),
            "feed_id": feedId.map(String.init),
            "tag_id": tagId.map(String.init),
            "state": state,
            "topic": topic
        ])
        return try await request(path: path, method: "GET", authenticated: true)
    }

    func fetchArticle(uid: String) async throws -> Article {
        try await request(path: "/api/v1/articles/\(percentEncodedPathSegment(uid))", method: "GET", authenticated: true)
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

    // MARK: - Phase 3: search, tags, topics

    func search(query: String) async throws -> [Article] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let path = urlPath("/api/v1/search", query: ["q": query])
        return try await request(path: path, method: "GET", authenticated: true)
    }

    func fetchTags() async throws -> [Tag] {
        try await request(path: "/api/v1/tags", method: "GET", authenticated: true)
    }

    func fetchTopics() async throws -> [Topic] {
        try await request(path: "/api/v1/topics", method: "GET", authenticated: true)
    }

    func fetchTopicArticles(term: String) async throws -> [Article] {
        try await request(path: "/api/v1/topics/\(percentEncodedPathSegment(term))", method: "GET", authenticated: true)
    }

    // MARK: - Phase 4a: feed catalog, recommendations, popular, mute rules

    func fetchFeedCatalog() async throws -> [CatalogGroup] {
        try await request(path: "/api/v1/feed_catalog", method: "GET", authenticated: true)
    }

    func fetchRecommendedFeeds() async throws -> [CatalogFeed] {
        try await request(path: "/api/v1/feed_catalog/recommended", method: "GET", authenticated: true)
    }

    /// `type`: "news" | "sports" | "podcasts" | "nature" | "youtube"
    func fetchPopularFeeds(type: String) async throws -> [Feed] {
        let path = urlPath("/api/v1/feeds/popular", query: ["type": type])
        return try await request(path: path, method: "GET", authenticated: true)
    }

    func fetchMuteRules() async throws -> [MuteRule] {
        try await request(path: "/api/v1/mute_rules", method: "GET", authenticated: true)
    }

    func addMuteRule(kind: String, value: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/mute_rules", method: "POST", jsonBody: ["kind": kind, "value": value], authenticated: true
        )
    }

    func removeMuteRule(kind: String, value: String) async throws {
        let path = urlPath("/api/v1/mute_rules", query: ["kind": kind, "value": value])
        let _: EmptyResponse = try await request(path: path, method: "DELETE", authenticated: true)
    }

    // MARK: - Phase 5: podcasts, YouTube

    func fetchPodcastFeeds() async throws -> [PodcastFeed] {
        try await request(path: "/api/v1/podcasts", method: "GET", authenticated: true)
    }

    func fetchYouTubeChannels() async throws -> [YouTubeChannel] {
        try await request(path: "/api/v1/youtube/channels", method: "GET", authenticated: true)
    }

    // MARK: - Phase 6a: sports

    func fetchSports() async throws -> [Sport] {
        try await request(path: "/api/v1/sports", method: "GET", authenticated: true)
    }

    func fetchSportsLeagues(sport: String) async throws -> [SportsLeague] {
        try await request(path: "/api/v1/sports/\(percentEncodedPathSegment(sport))/leagues", method: "GET", authenticated: true)
    }

    func fetchSportsTeams(sport: String, league: String) async throws -> [SportsTeam] {
        try await request(
            path: "/api/v1/sports/\(percentEncodedPathSegment(sport))/\(percentEncodedPathSegment(league))/teams",
            method: "GET", authenticated: true
        )
    }

    func fetchSportsOverview() async throws -> SportsOverview {
        try await request(path: "/api/v1/sports/overview", method: "GET", authenticated: true)
    }

    func fetchSportsTeamDetail(slug: String) async throws -> SportsTeamDetail {
        try await request(path: "/api/v1/sports/teams/\(percentEncodedPathSegment(slug))", method: "GET", authenticated: true)
    }

    func fetchSportsLeagueDetail(slug: String) async throws -> SportsLeagueDetail {
        try await request(path: "/api/v1/sports/leagues/\(percentEncodedPathSegment(slug))", method: "GET", authenticated: true)
    }

    func fetchSportsPlayerDetail(slug: String) async throws -> SportsPlayerDetail {
        try await request(path: "/api/v1/sports/players/\(percentEncodedPathSegment(slug))", method: "GET", authenticated: true)
    }

    private struct FollowResponse: Decodable { let ok: Bool; let followed: Bool }

    func followSportsTeam(slug: String) async throws {
        let _: FollowResponse = try await request(path: "/api/v1/sports/teams/follow", method: "POST", jsonBody: ["slug": slug], authenticated: true)
    }

    func unfollowSportsTeam(slug: String) async throws {
        let path = urlPath("/api/v1/sports/teams/follow", query: ["slug": slug])
        let _: FollowResponse = try await request(path: path, method: "DELETE", authenticated: true)
    }

    func followSportsLeague(slug: String) async throws {
        let _: FollowResponse = try await request(path: "/api/v1/sports/leagues/follow", method: "POST", jsonBody: ["slug": slug], authenticated: true)
    }

    func unfollowSportsLeague(slug: String) async throws {
        let path = urlPath("/api/v1/sports/leagues/follow", query: ["slug": slug])
        let _: FollowResponse = try await request(path: path, method: "DELETE", authenticated: true)
    }

    func followSportsPlayer(slug: String) async throws {
        let _: FollowResponse = try await request(path: "/api/v1/sports/players/follow", method: "POST", jsonBody: ["slug": slug], authenticated: true)
    }

    func unfollowSportsPlayer(slug: String) async throws {
        let path = urlPath("/api/v1/sports/players/follow", query: ["slug": slug])
        let _: FollowResponse = try await request(path: path, method: "DELETE", authenticated: true)
    }

    // MARK: - Phase 7: stocks

    func searchStocks(query: String) async throws -> [StockSearchResult] {
        let path = urlPath("/api/v1/stocks/search", query: ["q": query])
        return try await request(path: path, method: "GET", authenticated: true)
    }

    func fetchStockDetail(symbol: String) async throws -> StockDetail {
        try await request(path: "/api/v1/stocks/\(percentEncodedPathSegment(symbol))", method: "GET", authenticated: true)
    }

    func fetchStockNews(symbol: String) async throws -> [Article] {
        try await request(path: "/api/v1/stocks/\(percentEncodedPathSegment(symbol))/news", method: "GET", authenticated: true)
    }

    func fetchStockTicker() async throws -> [TickerEntry] {
        try await request(path: "/api/v1/stocks/ticker", method: "GET", authenticated: true)
    }

    private struct StockFollowResponse: Decodable { let ok: Bool; let followed: Bool }

    func followStock(symbol: String, name: String? = nil) async throws {
        var body: [String: Any] = ["symbol": symbol]
        if let name { body["name"] = name }
        let _: StockFollowResponse = try await request(path: "/api/v1/stocks/follow", method: "POST", jsonBody: body, authenticated: true)
    }

    func unfollowStock(symbol: String) async throws {
        let path = urlPath("/api/v1/stocks/follow", query: ["symbol": symbol])
        let _: StockFollowResponse = try await request(path: path, method: "DELETE", authenticated: true)
    }

    // MARK: - Phase 8a: radio

    func fetchRadioStations() async throws -> RadioStationsResponse {
        try await request(path: "/api/v1/radio/stations", method: "GET", authenticated: true)
    }

    private struct RadioFollowResponse: Decodable { let ok: Bool; let followed: Bool }

    func followRadioStation(id: Int) async throws {
        let _: RadioFollowResponse = try await request(path: "/api/v1/radio/follow", method: "POST", jsonBody: ["station_id": id], authenticated: true)
    }

    func unfollowRadioStation(id: Int) async throws {
        let path = urlPath("/api/v1/radio/follow", query: ["station_id": String(id)])
        let _: RadioFollowResponse = try await request(path: path, method: "DELETE", authenticated: true)
    }

    // MARK: - Phase 9: triage, digests

    func fetchTriageRuns() async throws -> [TriageSummary] {
        try await request(path: "/api/v1/triage", method: "GET", authenticated: true)
    }

    func fetchTriageDetail(id: Int) async throws -> TriageDetail {
        try await request(path: "/api/v1/triage/\(id)", method: "GET", authenticated: true)
    }

    func runTriage(topic: String? = nil) async throws -> TriageRunResult {
        var body: [String: Any] = [:]
        if let topic { body["topic"] = topic }
        return try await request(path: "/api/v1/triage", method: "POST", jsonBody: body, authenticated: true)
    }

    func fetchDigests() async throws -> [DigestSummary] {
        try await request(path: "/api/v1/digests", method: "GET", authenticated: true)
    }

    func fetchDigestDetail(id: Int) async throws -> DigestDetail {
        try await request(path: "/api/v1/digests/\(id)", method: "GET", authenticated: true)
    }

    func generateDigest() async throws -> DigestDetail {
        try await request(path: "/api/v1/digests", method: "POST", jsonBody: [:], authenticated: true)
    }

    func summarizeDigest(id: Int) async throws -> DigestDetail {
        try await request(path: "/api/v1/digests/\(id)/summarize", method: "POST", authenticated: true)
    }

    // MARK: - Phase 10: account

    func fetchAccount() async throws -> AccountInfo {
        try await request(path: "/api/v1/account", method: "GET", authenticated: true)
    }

    func updateDisplayName(_ displayName: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/account/display_name", method: "POST", jsonBody: ["display_name": displayName], authenticated: true
        )
    }

    struct RegenerateCodesResponse: Decodable { let ok: Bool; let recoveryCodes: [String] }

    func regenerateRecoveryCodes() async throws -> [String] {
        let response: RegenerateCodesResponse = try await request(
            path: "/api/v1/account/recovery_codes/regenerate", method: "POST", authenticated: true
        )
        return response.recoveryCodes
    }

    func fetchPasskeys() async throws -> [Passkey] {
        try await request(path: "/api/v1/account/passkeys", method: "GET", authenticated: true)
    }

    func revokePasskey(credentialId: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/account/passkeys/\(percentEncodedPathSegment(credentialId))", method: "DELETE", authenticated: true
        )
    }

    func deleteAccount(confirmUsername: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/account", method: "DELETE", jsonBody: ["confirm_username": confirmUsername], authenticated: true
        )
    }

    // MARK: - Phase 11: article detail parity (feedback, tag apply/remove)

    struct FeedbackResponse: Decodable { let ok: Bool; let feedback: Int }

    /// `value`: `1` (thumbs up), `-1` (thumbs down), or `0` (clear).
    func setArticleFeedback(uid: String, value: Int) async throws {
        let _: FeedbackResponse = try await request(
            path: "/api/v1/articles/\(percentEncodedPathSegment(uid))/feedback",
            method: "POST", jsonBody: ["value": value], authenticated: true
        )
    }

    func applyTag(uid: String, tagId: Int) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/articles/\(percentEncodedPathSegment(uid))/tags/\(tagId)", method: "POST", authenticated: true
        )
    }

    func removeTag(uid: String, tagId: Int) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/articles/\(percentEncodedPathSegment(uid))/tags/\(tagId)", method: "DELETE", authenticated: true
        )
    }

    // MARK: - Core request plumbing

    struct EmptyResponse: Decodable { let ok: Bool? }

    /// Builds `path?key=value&...`, skipping nil values, with each value
    /// percent-encoded (including `&`/`=`/`+`, which `.urlQueryAllowed`
    /// alone treats as already-legal query characters and would otherwise
    /// leave as literal delimiters inside a value like a search term).
    private func urlPath(_ path: String, query: [String: String?]) -> String {
        let pairs = query.compactMapValues { $0 }
        guard !pairs.isEmpty else { return path }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let encoded = pairs.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return "\(path)?\(encoded.joined(separator: "&"))"
    }

    private func percentEncodedPathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    /// `path` must already be fully percent-encoded (via `urlPath`/
    /// `percentEncodedPathSegment` above) — `URL(string:relativeTo:)`
    /// parses it as-is rather than re-encoding, so this can't
    /// double-encode the way round-tripping through URLComponents'
    /// unencoded `.query`/`.path` setters can.
    private func request<T: Decodable>(
        path: String, method: String, jsonBody: [String: Any]? = nil, authenticated: Bool
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidResponse }
        var req = URLRequest(url: url.absoluteURL)
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
