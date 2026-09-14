import Foundation

struct Sport: Identifiable, Codable, Hashable {
    let slug: String
    let name: String
    let emoji: String?
    let region: String?
    let blurb: String?

    var id: String { slug }
}

struct SportsLeague: Identifiable, Codable, Hashable {
    let slug: String
    let name: String
    let sport: String?
    let region: String?
    let country: String?
    let blurb: String?
    let format: String?

    var id: String { slug }
    var isTournament: Bool { format == "tournament" }
}

/// Covers three shapes from three different endpoints: a catalog team
/// (slug/name/players, no numeric id), a synced DB team (adds id/
/// leagueId/imageUrl), and a match's nested home/away team (same DB
/// shape). All-optional beyond slug+name so any of the three decode.
struct SportsTeam: Identifiable, Codable, Hashable {
    let dbId: Int?
    let slug: String
    let name: String
    let shortName: String?
    let location: String?
    let imageUrl: String?
    let leagueId: Int?
    let players: [String]?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case dbId = "id"
        case slug, name, shortName, location, imageUrl, leagueId, players
    }
}

struct SportsMatch: Identifiable, Codable, Hashable {
    let id: Int
    let leagueId: Int?
    let homeTeamId: Int?
    let awayTeamId: Int?
    let scheduledAt: String?
    let status: String?
    let homeScore: Int?
    let awayScore: Int?
    let period: String?
    let venue: String?
    let homeTeam: SportsTeam?
    let awayTeam: SportsTeam?
}

struct SportsStanding: Identifiable, Codable, Hashable {
    let id: Int
    let leagueId: Int?
    let teamId: Int?
    let groupName: String?
    let position: Int?
    let wins: Int?
    let losses: Int?
    let ties: Int?
    let winPercent: String?
    let pointsFor: Int?
    let pointsAgainst: Int?
    let pointDifferential: Int?
    let gamesBehind: String?
    let streak: String?
    let playoffSeed: Int?
}

struct SportsPlayer: Identifiable, Codable, Hashable {
    let dbId: Int?
    let sport: String?
    let slug: String
    let fullName: String
    let country: String?
    let imageUrl: String?
    let tour: String?
    let currentRank: Int?
    let previousRank: Int?
    let trend: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case dbId = "id"
        case sport, slug, fullName, country, imageUrl, tour, currentRank, previousRank, trend
    }
}

struct SportsOverview: Codable {
    let followedTeams: [SportsTeam]
    let followedLeagues: [SportsLeague]
    let followedPlayers: [SportsPlayer]
    let liveMatches: [SportsMatch]
}

struct SportsTeamDetail: Codable {
    let team: SportsTeam
    let league: SportsLeague?
    let standings: SportsStanding?
    let upcoming: [SportsMatch]
    let recentFinals: [SportsMatch]
    let mentions: [Article]
    let followed: Bool
}

struct SportsLeagueDetail: Codable {
    let league: SportsLeague
    let standings: [SportsStanding]
    let upcoming: [SportsMatch]
    let recentFinals: [SportsMatch]
    let teamsById: [String: SportsTeam]
    let followed: Bool
}

struct SportsPlayerDetail: Codable {
    let player: SportsPlayer
    let mentions: [Article]
    let followed: Bool
}
