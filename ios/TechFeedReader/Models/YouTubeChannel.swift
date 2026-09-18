import Foundation

struct YouTubeChannel: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let url: String
    let imageUrl: String?
    let videoCount: Int
    let latestAt: String?
    let latestUid: String?
    let latestUrl: String?
}
