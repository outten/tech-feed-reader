import SwiftUI

struct PodcastsView: View {
    @State private var feeds: [PodcastFeed] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(feeds) { feed in
            NavigationLink(value: feed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.title ?? feed.url)
                    Text("\(feed.episodeCount) episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Podcasts")
        .navigationDestination(for: PodcastFeed.self) { feed in
            ArticlesListView(title: feed.title ?? "Episodes", emptyTitle: "No Episodes Yet") {
                try await APIClient.shared.fetchArticles(feedId: feed.id)
            }
        }
        .overlay {
            if isLoading && feeds.isEmpty { ProgressView() }
            if !isLoading && feeds.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Podcasts Yet", systemImage: "mic")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Podcasts", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feeds = try await APIClient.shared.fetchPodcastFeeds()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
