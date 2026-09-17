import SwiftUI

struct SportsHomeView: View {
    @State private var overview: SportsOverview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            NavigationLink("Browse Sports", value: SportsBrowseRoot())
            NavigationLink("Tennis Rankings (ATP/WTA)", value: SportsTennisRankingsRoot())

            if let overview {
                if !overview.liveMatches.isEmpty {
                    Section("Live") {
                        ForEach(overview.liveMatches) { MatchRow(match: $0) }
                    }
                }
                if !overview.followedTeams.isEmpty {
                    Section("Followed Teams") {
                        ForEach(overview.followedTeams) { team in
                            NavigationLink(value: team) {
                                HStack(spacing: 8) {
                                    TeamLogo(imageURL: team.imageUrl.flatMap(URL.init))
                                    Text(team.name)
                                }
                            }
                        }
                    }
                }
                if !overview.followedLeagues.isEmpty {
                    Section("Followed Leagues") {
                        ForEach(overview.followedLeagues) { league in
                            NavigationLink(league.name, value: league)
                        }
                    }
                }
                if !overview.followedPlayers.isEmpty {
                    Section("Followed Players") {
                        ForEach(overview.followedPlayers) { player in
                            NavigationLink(value: player) {
                                HStack(spacing: 8) {
                                    TeamLogo(imageURL: player.imageUrl.flatMap(URL.init))
                                    Text(player.fullName)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sports")
        .overlay {
            if isLoading && overview == nil { ProgressView() }
        }
        .navigationDestination(for: SportsBrowseRoot.self) { _ in SportsBrowseView() }
        .navigationDestination(for: SportsTennisRankingsRoot.self) { _ in SportsTennisRankingsView() }
        .navigationDestination(for: Sport.self) { SportsLeaguesView(sport: $0) }
        .navigationDestination(for: SportsLeague.self) { league in
            SportsLeagueDetailView(sportSlug: league.sport ?? "", leagueSlug: league.slug, leagueName: league.name)
        }
        .navigationDestination(for: SportsTeam.self) { SportsTeamDetailView(slug: $0.slug, displayName: $0.name) }
        .navigationDestination(for: SportsPlayer.self) { SportsPlayerDetailView(slug: $0.slug, displayName: $0.fullName) }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            overview = try await APIClient.shared.fetchSportsOverview()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Marker value for the "Browse Sports" NavigationLink — SportsHomeView
/// registers all the sports-flow navigationDestination handlers, so
/// anything pushed further down (Sport → SportsLeague → SportsTeam/
/// SportsPlayer) resolves against the same NavigationStack.
struct SportsBrowseRoot: Hashable {}

/// Marker value for the "Tennis Rankings" NavigationLink — same pattern
/// as `SportsBrowseRoot` (Phase 17).
struct SportsTennisRankingsRoot: Hashable {}
