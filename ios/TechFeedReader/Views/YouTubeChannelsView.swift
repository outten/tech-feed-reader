import SwiftUI

struct YouTubeChannelsView: View {
    @State private var channels: [YouTubeChannel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(channels) { channel in
            NavigationLink(value: channel) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title ?? channel.url)
                    Text("\(channel.videoCount) videos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("YouTube")
        .navigationDestination(for: YouTubeChannel.self) { channel in
            ArticlesListView(title: channel.title ?? "Videos", emptyTitle: "No Videos Yet") {
                try await APIClient.shared.fetchArticles(feedId: channel.id)
            }
        }
        .overlay {
            if isLoading && channels.isEmpty { ProgressView() }
            if !isLoading && channels.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Channels Yet", systemImage: "play.rectangle")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Channels", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            channels = try await APIClient.shared.fetchYouTubeChannels()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
