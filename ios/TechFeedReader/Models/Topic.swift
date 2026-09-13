import Foundation

/// Only decodes `term`/`count` — TopicClusters.recent also embeds a
/// handful of representative articles per cluster, but the topics list
/// screen only needs the term + count; tapping a topic re-fetches full
/// Article objects via GET /api/v1/topics/:term instead.
struct Topic: Identifiable, Codable, Hashable {
    let term: String
    let count: Int

    var id: String { term }
}
