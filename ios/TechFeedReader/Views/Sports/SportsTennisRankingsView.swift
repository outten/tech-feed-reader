import SwiftUI

/// Phase 17 — the web app has a dedicated ATP/WTA rankings page
/// (`/sports/tennis`) with an inline follow toggle per row; iOS never
/// got an equivalent, so the only way to follow a player was via a
/// team's "Notable Players" list — which doesn't help for tennis,
/// since players aren't attached to a team at all. This is the
/// discoverable, direct path.
struct SportsTennisRankingsView: View {
    @State private var rankings: TennisRankings?
    @State private var followedSlugs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let rankings {
                if !rankings.atp.isEmpty {
                    Section("ATP") {
                        ForEach(rankings.atp) { player in playerRow(player) }
                    }
                }
                if !rankings.wta.isEmpty {
                    Section("WTA") {
                        ForEach(rankings.wta) { player in playerRow(player) }
                    }
                }
            }
        }
        .navigationTitle("Tennis Rankings")
        .navigationDestination(for: SportsPlayer.self) { SportsPlayerDetailView(slug: $0.slug, displayName: $0.fullName) }
        .overlay {
            if isLoading && rankings == nil { ProgressView() }
            if !isLoading && (rankings?.atp.isEmpty ?? true) && (rankings?.wta.isEmpty ?? true) && errorMessage == nil {
                ContentUnavailableView("No Rankings Yet", systemImage: "tennisball")
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func playerRow(_ player: SportsPlayer) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: player) {
                HStack(spacing: 10) {
                    TeamLogo(imageURL: player.imageUrl.flatMap(URL.init), size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.fullName)
                        if let country = player.country {
                            Text(country).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let rank = player.currentRank {
                        Text("#\(rank)").foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                Task { await toggleFollow(player) }
            } label: {
                Image(systemName: followedSlugs.contains(player.slug) ? "star.fill" : "star")
                    .foregroundStyle(followedSlugs.contains(player.slug) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rankings = try await APIClient.shared.fetchTennisRankings()
            followedSlugs = Set(rankings?.followedPlayerSlugs ?? [])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow(_ player: SportsPlayer) async {
        do {
            if followedSlugs.contains(player.slug) {
                try await APIClient.shared.unfollowSportsPlayer(slug: player.slug)
                followedSlugs.remove(player.slug)
            } else {
                try await APIClient.shared.followSportsPlayer(slug: player.slug)
                followedSlugs.insert(player.slug)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
