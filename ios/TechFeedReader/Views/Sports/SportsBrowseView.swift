import SwiftUI

struct SportsBrowseView: View {
    @State private var sports: [Sport] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(sports) { sport in
            NavigationLink(value: sport) {
                HStack {
                    if let emoji = sport.emoji { Text(emoji) }
                    Text(sport.name)
                }
            }
        }
        .navigationTitle("Browse Sports")
        .overlay {
            if isLoading && sports.isEmpty { ProgressView() }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Sports", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sports = try await APIClient.shared.fetchSports()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SportsLeaguesView: View {
    let sport: Sport
    @State private var leagues: [SportsLeague] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(leagues) { league in
            NavigationLink(value: league) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.name)
                    if league.isTournament {
                        Text("Tournament").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(sport.name)
        .overlay {
            if isLoading && leagues.isEmpty { ProgressView() }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Leagues", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            leagues = try await APIClient.shared.fetchSportsLeagues(sport: sport.slug)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
