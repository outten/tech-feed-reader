import SwiftUI

struct SportsPlayerDetailView: View {
    let slug: String
    let displayName: String

    @State private var detail: SportsPlayerDetail?
    @State private var isFollowed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let detail {
                if let rank = detail.player.currentRank {
                    Section("Ranking") {
                        Text("#\(rank)")
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
        .navigationTitle(detail?.player.fullName ?? displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isFollowed ? "Unfollow" : "Follow") {
                    Task { await toggleFollow() }
                }
            }
        }
        .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
        .overlay {
            if isLoading && detail == nil { ProgressView() }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.fetchSportsPlayerDetail(slug: slug)
            isFollowed = detail?.followed ?? false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow() async {
        do {
            if isFollowed {
                try await APIClient.shared.unfollowSportsPlayer(slug: slug)
            } else {
                try await APIClient.shared.followSportsPlayer(slug: slug)
            }
            isFollowed.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
