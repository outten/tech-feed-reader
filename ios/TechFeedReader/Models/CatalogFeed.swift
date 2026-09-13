import Foundation

struct CatalogFeed: Codable, Hashable {
    let url: String
    let title: String
    let blurb: String?
}

struct CatalogGroup: Identifiable, Codable, Hashable {
    let category: String
    let label: String
    let feeds: [CatalogFeed]

    var id: String { category }
}
