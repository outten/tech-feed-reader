import SwiftUI

struct TopicsListView: View {
    @State private var topics: [Topic] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(topics) { topic in
            NavigationLink(value: topic) {
                HStack {
                    Text(topic.term)
                    Spacer()
                    Text("\(topic.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Topics")
        .navigationDestination(for: Topic.self) { topic in
            ArticlesListView(title: topic.term, emptyTitle: "No Articles For This Topic") {
                try await APIClient.shared.fetchTopicArticles(term: topic.term)
            }
        }
        .overlay {
            if isLoading && topics.isEmpty { ProgressView() }
            if !isLoading && topics.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Topics Yet", systemImage: "square.grid.2x2")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Topics", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            topics = try await APIClient.shared.fetchTopics()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
