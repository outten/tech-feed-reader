import SwiftUI

/// Phase 15 — "what's short enough for my commute?" Mirrors the web
/// `/bus` route: podcast episodes at or under a max-minutes cutoff.
struct BusModeView: View {
    @State private var maxMinutes: Double = 15
    @State private var articles: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Stepper("Max \(Int(maxMinutes)) min", value: $maxMinutes, in: 1...90, step: 5)
            }
            ForEach(articles) { article in
                NavigationLink(value: article) {
                    ArticleRow(article: article)
                }
            }
        }
        .navigationTitle("Bus Mode")
        .navigationDestination(for: Article.self) { article in
            ArticleDetailView(article: article)
        }
        .overlay {
            if isLoading && articles.isEmpty { ProgressView() }
            if !isLoading && articles.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Short Episodes", systemImage: "bus")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Episodes", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task(id: maxMinutes) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await APIClient.shared.fetchBusMode(maxMinutes: Int(maxMinutes))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
