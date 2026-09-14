import Foundation

struct AccountInfo: Codable {
    let username: String
    let displayName: String?
    let passkeyCount: Int
    let recoveryCodesRemaining: Int
    let calendarUrl: String
}

struct Passkey: Identifiable, Codable, Hashable {
    let credentialId: String
    let label: String?
    let createdAt: String?
    let lastUsedAt: String?

    var id: String { credentialId }
}
