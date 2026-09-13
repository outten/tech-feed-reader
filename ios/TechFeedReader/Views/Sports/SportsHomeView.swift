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

            if let overview {
                if !overview.liveMatches.isEmpty {
                    Section("Live") {
                        ForEach(overview.liveMatches) { MatchRow(match: $0) }
                    }
                }
                if !overview.followedTeams.isEmpty {
                    Section("Followed Teams") {
                        ForEach(overview.followedTeams) { team in
                            NavigationLink(team.name, value: team)
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
                            NavigationLink(player.fullName, value: player)
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
