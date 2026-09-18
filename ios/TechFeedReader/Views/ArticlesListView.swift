import SwiftUI

/// Generic "list of articles from some source" screen — feeds, bookmarks,
/// a tag, or a topic all just need "fetch some articles, show a list,
/// push to detail on tap." One view instead of four near-duplicates.
struct ArticlesListView: View {
    let title: String
    let emptyTitle: String
    let fetch: () async throws -> [Article]

    @State private var articles: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(title: String, emptyTitle: String = "No Articles Yet", fetch: @escaping () async throws -> [Article]) {
        self.title = title
        self.emptyTitle = emptyTitle
        self.fetch = fetch
    }

    var body: some View {
        List(articles) { article in
            NavigationLink(value: article) {
                ArticleRow(article: article)
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: Article.self) { article in
            ArticleDetailView(article: article)
        }
        .overlay {
            if isLoading && articles.isEmpty { ProgressView() }
            if !isLoading && articles.isEmpty && errorMessage == nil {
                ContentUnavailableView(emptyTitle, systemImage: "doc.text")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Articles", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        // Keyed by title (not a bare .task) so switching source — e.g. one
        // feed to another — reliably reloads even though SwiftUI may reuse
        // this view's identity across switch-case re-renders in MainView.
        .task(id: title) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await fetch()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
