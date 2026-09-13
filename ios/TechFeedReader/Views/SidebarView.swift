import SwiftUI

/// The sidebar column of MainView's NavigationSplitView: a fixed
/// "Library" section (Bookmarks/Search/Tags/Topics — Phase 3) above the
/// user's subscribed feeds (Phase 1).
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @State private var feeds: [Feed] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddFeed = false
    @State private var newFeedURL = ""

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Bookmarks", systemImage: "bookmark").tag(SidebarItem.bookmarks)
                Label("Search", systemImage: "magnifyingglass").tag(SidebarItem.search)
                Label("Tags", systemImage: "tag").tag(SidebarItem.tags)
                Label("Topics", systemImage: "square.grid.2x2").tag(SidebarItem.topics)
            }
            Section("Browse") {
                Label("Podcasts", systemImage: "mic").tag(SidebarItem.podcasts)
                Label("YouTube", systemImage: "play.rectangle").tag(SidebarItem.youtube)
            }
            Section("Feeds") {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(feeds) { feed in
                    Text(feed.title ?? feed.url)
                        .tag(SidebarItem.feed(feed))
                }
                .onDelete(perform: unsubscribe)
            }
            Section("Manage") {
                Label("Discover Feeds", systemImage: "sparkle.magnifyingglass").tag(SidebarItem.discoverFeeds)
                Label("Mute Rules", systemImage: "speaker.slash").tag(SidebarItem.muteRules)
            }
        }
        .navigationTitle("Tech Feed Reader")
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
