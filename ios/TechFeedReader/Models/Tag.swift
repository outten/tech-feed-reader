import Foundation

struct Tag: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let matchKind: String
    let matchValue: String
}
