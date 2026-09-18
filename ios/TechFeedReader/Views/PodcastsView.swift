import SwiftUI

/// Two sections, mirroring the web app's `/podcasts` page order: recent
/// episodes (image-led cards) on top, subscribed shows (cover-art grid)
/// below (Phase 16 — was a single plain-text list of shows before).
struct PodcastsView: View {
    @State private var shows: [PodcastFeed] = []
    @State private var recentEpisodes: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding(.horizontal)
                }

                if !recentEpisodes.isEmpty {
                    sectionHeader("Recent Episodes")
                    LazyVStack(spacing: 14) {
                        ForEach(recentEpisodes) { article in
                            NavigationLink(value: article) {
                                ArticleRow(article: article)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }

                if !shows.isEmpty {
                    sectionHeader("Subscribed Shows")
                    LazyVGrid(columns: showGridColumns, spacing: 16) {
                        ForEach(shows) { show in
                            NavigationLink(value: show) {
                                ShowGridCard(
                                    imageURL: show.imageUrl.flatMap(URL.init),
                                    title: show.title ?? show.url,
                                    meta: "\(show.episodeCount) episodes"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Podcasts")
        .navigationDestination(for: PodcastFeed.self) { feed in
            ArticlesListView(title: feed.title ?? "Episodes", emptyTitle: "No Episodes Yet") {
                try await APIClient.shared.fetchArticles(feedId: feed.id)
            }
        }
        .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
        .overlay {
            if isLoading && shows.isEmpty { ProgressView() }
            if !isLoading && shows.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Podcasts Yet", systemImage: "mic")
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .padding(.horizontal)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let showsResult = APIClient.shared.fetchPodcastFeeds()
            async let episodesResult = APIClient.shared.fetchArticles(kind: "podcast")
            shows = try await showsResult
            recentEpisodes = try await episodesResult
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
