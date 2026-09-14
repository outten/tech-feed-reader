import SwiftUI

struct TagsListView: View {
    @State private var tags: [Tag] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(tags) { tag in
            NavigationLink(tag.name, value: tag)
        }
        .navigationTitle("Tags")
        .navigationDestination(for: Tag.self) { tag in
            ArticlesListView(title: tag.name, emptyTitle: "No Articles For This Tag") {
                try await APIClient.shared.fetchArticles(tagId: tag.id)
            }
        }
        .overlay {
            if isLoading && tags.isEmpty { ProgressView() }
            if !isLoading && tags.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Tags Yet", systemImage: "tag")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Tags", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tags = try await APIClient.shared.fetchTags()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
