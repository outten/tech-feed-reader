import Foundation

/// GET /api/v1/triage list rows — slim, no must_read/optional/skip.
struct TriageSummary: Identifiable, Codable, Hashable {
    let id: Int
    let generatedAt: String?
    let unreadCount: Int?
    let status: String?
    let model: String?
    let topic: String?
}

struct TriageEntry: Identifiable, Codable, Hashable {
    let uid: String
    let rationale: String?
    let article: Article?

    var id: String { uid }
}

/// GET /api/v1/triage/:id — full row with entries resolved to articles.
struct TriageDetail: Codable {
    let id: Int
    let generatedAt: String?
    let unreadCount: Int?
    let status: String?
    let model: String?
    let mustRead: [TriageEntry]
    let optional: [TriageEntry]
    let skip: [TriageEntry]
}

/// POST /api/v1/triage response.
struct TriageRunResult: Codable {
    let status: String
    let id: Int?
    let triage: TriageDetail?
}
