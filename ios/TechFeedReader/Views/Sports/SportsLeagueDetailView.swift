import SwiftUI

struct SportsLeagueDetailView: View {
    let sportSlug: String
    let leagueSlug: String
    let leagueName: String

    @State private var detail: SportsLeagueDetail?
    @State private var teams: [SportsTeam] = []
    @State private var followedTeamSlugs: Set<String> = []
    @State private var isFollowed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let detail {
                if !detail.standings.isEmpty {
                    Section("Standings") {
                        ForEach(detail.standings) { standing in
                            HStack {
                                Text(teamName(for: standing.teamId))
                                Spacer()
                                if let position = standing.position { Text("#\(position)").foregroundStyle(.secondary) }
                                if let wins = standing.wins, let losses = standing.losses {
                                    Text("\(wins)-\(losses)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !detail.upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(detail.upcoming) { MatchRow(match: $0, teamsById: detail.teamsById) }
                    }
                }
                if !detail.recentFinals.isEmpty {
                    Section("Recent Results") {
                        ForEach(detail.recentFinals) { MatchRow(match: $0, teamsById: detail.teamsById) }
                    }
                }
            }
            if !teams.isEmpty {
                Section("Teams") {
                    ForEach(teams) { team in
                        HStack {
                            NavigationLink(value: team) {
                                HStack(spacing: 8) {
                                    TeamLogo(imageURL: team.imageUrl.flatMap(URL.init))
                                    Text(team.name)
                                }
                            }
                            Spacer()
                            if followedTeamSlugs.contains(team.slug) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Follow") { Task { await followTeam(team) } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(leagueName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isFollowed ? "Unfollow" : "Follow") {
                    Task { await toggleFollow() }
                }
            }
        }
        .overlay {
            if isLoading && detail == nil { ProgressView() }
        }
        .task { await load() }
    }

    private func teamName(for teamId: Int?) -> String {
        guard let teamId else { return "Unknown" }
        return detail?.teamsById[String(teamId)]?.name ?? "Unknown"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailResult = APIClient.shared.fetchSportsLeagueDetail(slug: leagueSlug)
            async let teamsResult = APIClient.shared.fetchSportsTeams(sport: sportSlug, league: leagueSlug)
            detail = try await detailResult
            teams = try await teamsResult
            isFollowed = detail?.followed ?? false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow() async {
        do {
            if isFollowed {
                try await APIClient.shared.unfollowSportsLeague(slug: leagueSlug)
            } else {
                try await APIClient.shared.followSportsLeague(slug: leagueSlug)
            }
            isFollowed.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func followTeam(_ team: SportsTeam) async {
        do {
            try await APIClient.shared.followSportsTeam(slug: team.slug)
            followedTeamSlugs.insert(team.slug)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
