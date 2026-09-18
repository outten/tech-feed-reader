import Foundation

struct PodcastFeed: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let url: String
    let imageUrl: String?
    let episodeCount: Int
    let latestAt: String?
}
