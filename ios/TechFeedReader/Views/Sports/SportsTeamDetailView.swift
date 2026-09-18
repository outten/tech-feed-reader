import SwiftUI

struct SportsTeamDetailView: View {
    let slug: String
    let displayName: String

    @State private var detail: SportsTeamDetail?
    @State private var isFollowed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let detail {
                if let imageURL = detail.team.imageUrl.flatMap(URL.init) {
                    HStack {
                        Spacer()
                        AsyncImage(url: imageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 88, height: 88)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                if let standing = detail.standings {
                    Section("Standing") {
                        HStack {
                            if let position = standing.position { Text("#\(position)") }
                            if let wins = standing.wins, let losses = standing.losses {
                                Spacer()
                                Text("\(wins)-\(losses)")
                            }
                        }
                    }
                }
                if !detail.upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(detail.upcoming) { MatchRow(match: $0) }
                    }
                }
                if !detail.recentFinals.isEmpty {
                    Section("Recent Results") {
                        ForEach(detail.recentFinals) { MatchRow(match: $0) }
                    }
                }
                if let players = detail.team.players, !players.isEmpty {
                    Section("Notable Players") {
                        ForEach(players, id: \.self) { name in
                            NavigationLink(name, value: SportsPlayer(dbId: nil, sport: nil, slug: "\(slug)-\(slugify(name))", fullName: name, country: nil, imageUrl: nil, tour: nil, currentRank: nil, previousRank: nil, trend: nil))
                        }
                    }
                }
                if !detail.mentions.isEmpty {
                    Section("Mentions") {
                        ForEach(detail.mentions) { article in
                            NavigationLink(value: article) {
                                ArticleRow(article: article)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(detail?.team.name ?? displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isFollowed ? "Unfollow" : "Follow") {
                    Task { await toggleFollow() }
                }
            }
        }
        .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
        .navigationDestination(for: SportsPlayer.self) { SportsPlayerDetailView(slug: $0.slug, displayName: $0.fullName) }
        .overlay {
            if isLoading && detail == nil { ProgressView() }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.fetchSportsTeamDetail(slug: slug)
            isFollowed = detail?.followed ?? false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow() async {
        do {
            if isFollowed {
                try await APIClient.shared.unfollowSportsTeam(slug: slug)
            } else {
                try await APIClient.shared.followSportsTeam(slug: slug)
            }
            isFollowed.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
