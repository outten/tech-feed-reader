import SwiftUI

/// Phase 15 — wraps the generic article list with per-feed refresh-now
/// and relevance-weight controls, matching the web app's per-feed
/// weighting UI. A thin toolbar addition rather than a fork of
/// `ArticlesListView`, which every other list screen still uses as-is.
struct FeedArticlesView: View {
    let feed: Feed
    @State private var weight: Double
    @State private var errorMessage: String?

    init(feed: Feed) {
        self.feed = feed
        _weight = State(initialValue: feed.weight ?? 1.0)
    }

    var body: some View {
        ArticlesListView(title: feed.title ?? feed.url) {
            try await APIClient.shared.fetchArticles(feedId: feed.id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Refresh Now") { Task { await refresh() } }
                    Button("Boost (\(weightLabel))") { Task { await adjustWeight("up") } }
                    Button("Lower (\(weightLabel))") { Task { await adjustWeight("down") } }
                    Button("Reset Weight") { Task { await adjustWeight("reset") } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var weightLabel: String {
        String(format: "%.2g×", weight)
    }

    private func refresh() async {
        do {
            try await APIClient.shared.refreshFeed(id: feed.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adjustWeight(_ direction: String) async {
        do {
            weight = try await APIClient.shared.adjustFeedWeight(id: feed.id, direction: direction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
