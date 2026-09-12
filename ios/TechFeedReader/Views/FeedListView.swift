import SwiftUI

struct FeedListView: View {
    @Binding var selectedFeed: Feed?
    @State private var feeds: [Feed] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddFeed = false
    @State private var newFeedURL = ""

    var body: some View {
        List(selection: $selectedFeed) {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(feeds) { feed in
                Text(feed.title ?? feed.url)
                    .tag(feed)
            }
            .onDelete(perform: unsubscribe)
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddFeed = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if isLoading && feeds.isEmpty { ProgressView() }
            if !isLoading && feeds.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Feeds Yet", systemImage: "tray")
            }
        }
        .refreshable { await loadFeeds() }
        .task { await loadFeeds() }
        .alert("Add a Feed", isPresented: $showingAddFeed) {
            TextField("https://example.com/feed.xml", text: $newFeedURL)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { newFeedURL = "" }
            Button("Add") { Task { await addFeed() } }
        }
    }

    private func loadFeeds() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feeds = try await APIClient.shared.fetchFeeds()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addFeed() async {
        let url = newFeedURL.trimmingCharacters(in: .whitespaces)
        newFeedURL = ""
        guard !url.isEmpty else { return }
        do {
            let feed = try await APIClient.shared.subscribe(url: url)
            feeds.append(feed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unsubscribe(at offsets: IndexSet) {
        let toRemove = offsets.map { feeds[$0] }
        feeds.remove(atOffsets: offsets)
        Task {
            for feed in toRemove {
                try? await APIClient.shared.unsubscribe(feedId: feed.id)
            }
        }
    }
}
