import Foundation

/// GET /api/v1/digests list rows — slim.
struct DigestSummary: Identifiable, Codable, Hashable {
    let id: Int
    let generatedAt: String?
    let windowHours: Int?
    let articleCount: Int?
    let subject: String?
}

/// GET /api/v1/digests/:id and POST /api/v1/digests — full row.
struct DigestDetail: Codable {
    let id: Int
    let generatedAt: String?
    let windowHours: Int?
    let articleCount: Int?
    let subject: String?
    let textBody: String?
    let htmlBody: String?
    let llmSummary: String?
    let llmModel: String?
}
