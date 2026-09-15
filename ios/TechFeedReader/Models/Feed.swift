import Foundation

struct Feed: Identifiable, Codable, Hashable {
    let id: Int
    let url: String
    let title: String?
    let topic: String?
    let imageUrl: String?
    // Phase 15 — per-user relevance weight (For-You ranker input); nil
    // on responses that don't merge it in (e.g. the subscribe response).
    let weight: Double?
}
