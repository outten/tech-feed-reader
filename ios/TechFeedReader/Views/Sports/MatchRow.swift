import SwiftUI

/// Renders a match using nested home/away team data when present
/// (overview/live matches), falling back to a teamsById lookup
/// (league detail's upcoming/recentFinals, which only carry team ids).
struct MatchRow: View {
    let match: SportsMatch
    var teamsById: [String: SportsTeam] = [:]

    private var homeName: String {
        match.homeTeam?.name ?? match.homeTeamId.flatMap { teamsById[String($0)]?.name } ?? "TBD"
    }
    private var awayName: String {
        match.awayTeam?.name ?? match.awayTeamId.flatMap { teamsById[String($0)]?.name } ?? "TBD"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(awayName) @ \(homeName)")
                Spacer()
                if let homeScore = match.homeScore, let awayScore = match.awayScore {
                    Text("\(awayScore)-\(homeScore)").fontWeight(.semibold)
                }
            }
            HStack {
                if let status = match.status {
                    Text(status.capitalized)
                        .font(.caption)
                        .foregroundStyle(status == "live" ? .red : .secondary)
                }
                if let scheduledAt = match.scheduledAt {
                    Text(scheduledAt).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
