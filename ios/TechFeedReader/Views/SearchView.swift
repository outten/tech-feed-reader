import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var articles: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(articles) { article in
            NavigationLink(value: article) {
                ArticleRow(article: article)
            }
        }
        .navigationTitle("Search")
        .navigationDestination(for: Article.self) { article in
            ArticleDetailView(article: article)
        }
        .searchable(text: $query, prompt: "Search your articles")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty { articles = [] }
        }
        .overlay {
            if isLoading { ProgressView() }
            if let errorMessage {
                ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if !isLoading && articles.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await APIClient.shared.search(query: query)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
