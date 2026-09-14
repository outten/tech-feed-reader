import Foundation

/// mute_rules has no surrogate id — (user_id, kind, value) is the
/// primary key, so `kind`+`value` together are this rule's identity.
struct MuteRule: Identifiable, Codable, Hashable {
    let kind: String
    let value: String

    var id: String { "\(kind):\(value)" }
}
