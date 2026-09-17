import SwiftUI

/// Small team-logo thumbnail, shared by every place a team appears
/// inline (Phase 17 — team logos were decoded from the backend but
/// never rendered anywhere in the Sports screens).
struct TeamLogo: View {
    let imageURL: URL?
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.clear
                }
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

/// Renders a match using nested home/away team data when present
/// (overview/live matches), falling back to a teamsById lookup
/// (league detail's upcoming/recentFinals, which only carry team ids).
struct MatchRow: View {
    let match: SportsMatch
    var teamsById: [String: SportsTeam] = [:]

    private var homeTeam: SportsTeam? {
        match.homeTeam ?? match.homeTeamId.flatMap { teamsById[String($0)] }
    }
    private var awayTeam: SportsTeam? {
        match.awayTeam ?? match.awayTeamId.flatMap { teamsById[String($0)] }
    }
    private var homeName: String { homeTeam?.name ?? "TBD" }
    private var awayName: String { awayTeam?.name ?? "TBD" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TeamLogo(imageURL: awayTeam?.imageUrl.flatMap(URL.init))
                Text(awayName)
                Text("@").foregroundStyle(.secondary)
                TeamLogo(imageURL: homeTeam?.imageUrl.flatMap(URL.init))
                Text(homeName)
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
