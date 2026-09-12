import Foundation

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

    // read_state columns — 0/1 from the Postgres LEFT JOIN. `var` so the
    // detail view can flip them optimistically after a successful API call
    // without reconstructing the whole struct.
    var read: Int?
    var bookmarked: Int?
    var archived: Int?

    var isRead: Bool { (read ?? 0) != 0 }
    var isBookmarked: Bool { (bookmarked ?? 0) != 0 }
    var isArchived: Bool { (archived ?? 0) != 0 }
}
