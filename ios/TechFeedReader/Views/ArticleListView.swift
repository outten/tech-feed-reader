import SwiftUI

struct ArticleListView: View {
    let feed: Feed

    @State private var articles: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(articles) { article in
            NavigationLink(value: article) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .fontWeight(article.isRead ? .regular : .semibold)
                        .lineLimit(2)
                    if let publishedAt = article.publishedAt {
                        Text(publishedAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(feed.title ?? "Articles")
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
        .refreshable { await loadArticles() }
        .task(id: feed.id) { await loadArticles() }
    }

    private func loadArticles() async {
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await APIClient.shared.fetchArticles(feedId: feed.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
