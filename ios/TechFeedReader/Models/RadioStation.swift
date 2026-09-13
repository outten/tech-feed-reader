import Foundation

struct RadioStation: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let genre: String?
    let streamUrl: String
    let imageUrl: String?
    let homeUrl: String?
    let catalog: String?
}

struct RadioGroup: Identifiable, Codable, Hashable {
    let group: String
    let stations: [RadioStation]

    var id: String { group }
}

struct RadioStationsResponse: Codable {
    let groups: [RadioGroup]
    let followedIds: [Int]
}
