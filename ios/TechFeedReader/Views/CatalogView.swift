import SwiftUI

struct CatalogView: View {
    private static let popularTypes = ["news", "sports", "podcasts", "nature", "youtube"]

    @State private var groups: [CatalogGroup] = []
    @State private var recommended: [CatalogFeed] = []
    @State private var subscribedURLs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var popularType = "news"
    @State private var popularFeeds: [Feed] = []

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if !recommended.isEmpty {
                Section("Recommended for You") {
                    ForEach(recommended, id: \.url) { feed in
                        catalogRow(for: feed)
                    }
                }
            }
            Section("Popular") {
                Picker("Type", selection: $popularType) {
                    ForEach(Self.popularTypes, id: \.self) { Text($0.capitalized) }
                }
                .pickerStyle(.segmented)
                .task(id: popularType) { await loadPopular() }

                ForEach(popularFeeds) { feed in
                    catalogRow(for: CatalogFeed(url: feed.url, title: feed.title ?? feed.url, blurb: nil))
                }
            }
            ForEach(groups) { group in
                Section(group.label) {
                    ForEach(group.feeds, id: \.url) { feed in
                        catalogRow(for: feed)
                    }
                }
            }
        }
        .navigationTitle("Discover Feeds")
        .overlay {
            if isLoading && groups.isEmpty { ProgressView() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func catalogRow(for feed: CatalogFeed) -> some View {
        let isSubscribed = subscribedURLs.contains(feed.url)
        Button {
            Task { await subscribe(to: feed) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.title).foregroundStyle(.primary)
                    if let blurb = feed.blurb {
                        Text(blurb).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSubscribed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .disabled(isSubscribed)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let catalog = APIClient.shared.fetchFeedCatalog()
            async let subscribed = APIClient.shared.fetchFeeds()
            async let recs = APIClient.shared.fetchRecommendedFeeds()
            groups = try await catalog
            subscribedURLs = Set(try await subscribed.map { $0.url })
            recommended = try await recs
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPopular() async {
        do {
            popularFeeds = try await APIClient.shared.fetchPopularFeeds(type: popularType)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscribe(to feed: CatalogFeed) async {
        do {
            _ = try await APIClient.shared.subscribe(url: feed.url)
            subscribedURLs.insert(feed.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
