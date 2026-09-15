import Foundation

struct OnboardingChip: Identifiable, Codable, Hashable {
    let topic: String
    let label: String
    let blurb: String?
    let emoji: String?

    var id: String { topic }
}
