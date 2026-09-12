import Foundation

struct Feed: Identifiable, Codable, Hashable {
    let id: Int
    let url: String
    let title: String?
    let topic: String?
    let imageUrl: String?
}
