import Foundation

struct ArticleSummary: Codable, Hashable {
    let extractive: String?
    let llm: String?
    let llmModel: String?
}

struct Article: Identifiable, Codable, Hashable {
    let id: Int
    let uid: String
    let feedId: Int
    let title: String
    let url: String
    let author: String?
    let publishedAt: String?
    let contentHtml: String?
    let contentText: String?
    let imageUrl: String?

    // Podcast enclosure — nil for a plain article.
    let audioUrl: String?
    let audioMimeType: String?
    let audioDurationSeconds: Int?

    var isPodcastEpisode: Bool { audioUrl != nil }

    // Only present on GET /api/v1/articles/:uid (Phase 11), nil in list
    // responses — no join cost paid for rows the user never opens.
    var summary: ArticleSummary?
    var tags: [Tag]?
    var feed: Feed?

    // read_state columns — 0/1 from the Postgres LEFT JOIN. `var` so the
    // detail view can flip them optimistically after a successful API call
    // without reconstructing the whole struct.
    var read: Int?
    var bookmarked: Int?
    var archived: Int?
    var feedback: Int?

    var isRead: Bool { (read ?? 0) != 0 }
    var isBookmarked: Bool { (bookmarked ?? 0) != 0 }
    var isArchived: Bool { (archived ?? 0) != 0 }
}
