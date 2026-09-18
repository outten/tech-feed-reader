import SwiftUI

/// Two sections, mirroring the web app's `/youtube` page order: recent
/// videos (16:9 thumbnail grid) on top, subscribed channels (cover-art
/// grid, sharing `ShowGridCard` with Podcasts) below (Phase 16 — the
/// recent-videos grid has no prior iOS equivalent at all).
struct YouTubeChannelsView: View {
    @State private var channels: [YouTubeChannel] = []
    @State private var recentVideos: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding(.horizontal)
                }

                if !recentVideos.isEmpty {
                    sectionHeader("Recent Videos")
                    LazyVGrid(columns: videoGridColumns, spacing: 16) {
                        ForEach(recentVideos) { article in
                            NavigationLink(value: article) {
                                VideoGridCard(
                                    imageURL: article.thumbnailURL,
                                    title: article.title,
                                    meta: article.relativePublishedTime ?? "",
                                    isRead: article.isRead
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if !channels.isEmpty {
                    sectionHeader("Subscribed Channels")
                    LazyVGrid(columns: showGridColumns, spacing: 16) {
                        ForEach(channels) { channel in
                            NavigationLink(value: channel) {
                                ShowGridCard(
                                    imageURL: channel.imageUrl.flatMap(URL.init),
                                    title: channel.title ?? channel.url,
                                    meta: "\(channel.videoCount) videos"
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
        .navigationTitle("YouTube")
        .navigationDestination(for: YouTubeChannel.self) { channel in
            ArticlesListView(title: channel.title ?? "Videos", emptyTitle: "No Videos Yet") {
                try await APIClient.shared.fetchArticles(feedId: channel.id)
            }
        }
        .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
        .overlay {
            if isLoading && channels.isEmpty { ProgressView() }
            if !isLoading && channels.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Channels Yet", systemImage: "play.rectangle")
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
            async let channelsResult = APIClient.shared.fetchYouTubeChannels()
            async let videosResult = APIClient.shared.fetchArticles(kind: "youtube")
            channels = try await channelsResult
            recentVideos = try await videosResult
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
