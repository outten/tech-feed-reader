import SwiftUI

/// Phase 12 — the plain "All Articles" screen (`GET /articles` on the web,
/// with no feed/tag/topic-cluster scoping). Unlike `ArticlesListView`, this
/// screen owns its own filter state and pagination since neither is shared
/// by any other list screen today.
struct ReadingRiverView: View {
    /// Mirrors `FeedCatalog::TOPICS` in app/feed_catalog.rb — kept as a
    /// small static list rather than a new endpoint since the backend need
    /// for this phase was deliberately kept minimal (kind + sort only).
    static let topics: [(key: String, label: String)] = [
        ("technology", "Technology"), ("sports", "Sports"), ("nature", "Nature & Documentary"),
        ("humor", "Humor"), ("finance", "Finance & Markets"), ("world_news", "World News"),
        ("science", "Science"), ("gaming", "Gaming"), ("food", "Food & Cooking"),
        ("npr", "NPR"), ("pbs", "PBS"), ("world_public", "World Public Media"),
        ("health", "Health & Wellness"), ("arts", "Arts & Culture"), ("history", "History"),
        ("environment", "Environment & Climate"), ("business", "Business"), ("travel", "Travel"),
        ("social", "Social & Newsletters"), ("politics", "Politics & Policy"),
        ("design", "Design & UX"), ("automotive", "Automotive & EVs")
    ]

    private static let perPage = 50
    private static let stateOptions = ["all", "unread", "bookmarked", "archived"]

    @State private var articles: [Article] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var stateFilter = "all"
    @State private var podcastsOnly = false
    @State private var topicFilter: String?
    @State private var forYouSort = false

    var body: some View {
        List {
            Section {
                Picker("State", selection: $stateFilter) {
                    ForEach(Self.stateOptions, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(forYouSort)

                Toggle("For You (relevance)", isOn: $forYouSort)
                Toggle("Podcasts only", isOn: $podcastsOnly)

                Picker("Topic", selection: $topicFilter) {
                    Text("All Topics").tag(String?.none)
                    ForEach(Self.topics, id: \.key) { Text($0.label).tag(String?.some($0.key)) }
                }
            }
            .listRowSeparator(.hidden)

            ForEach(articles) { article in
                NavigationLink(value: article) {
                    ArticleRow(article: article)
                }
            }

            if !articles.isEmpty, articles.count % Self.perPage == 0 {
                Button {
                    Task { await loadMore() }
                } label: {
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Text("Load More")
                    }
                }
                .disabled(isLoadingMore)
            }
        }
        .navigationTitle("All Articles")
        .navigationDestination(for: Article.self) { article in
            ArticleDetailView(article: article)
        }
        .overlay {
            if isLoading && articles.isEmpty { ProgressView() }
            if !isLoading && articles.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Articles Yet", systemImage: "doc.text")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Articles", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .onChange(of: stateFilter) { Task { await reload() } }
        .onChange(of: podcastsOnly) { Task { await reload() } }
        .onChange(of: topicFilter) { Task { await reload() } }
        .onChange(of: forYouSort) {
            if forYouSort { stateFilter = "unread" }
            Task { await reload() }
        }
    }

    private func reload() async {
        page = 1
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await fetchPage(1)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let nextPage = page + 1
            let more = try await fetchPage(nextPage)
            articles.append(contentsOf: more)
            page = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPage(_ page: Int) async throws -> [Article] {
        try await APIClient.shared.fetchArticles(
            state: stateFilter,
            topic: topicFilter,
            kind: podcastsOnly ? "podcast" : nil,
            sort: forYouSort ? "relevance" : nil,
            page: page
        )
    }
}
