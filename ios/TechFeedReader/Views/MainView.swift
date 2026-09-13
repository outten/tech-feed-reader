import SwiftUI

/// iPhone: NavigationSplitView collapses to a single navigable column.
/// iPad: sidebar (Library + Feeds) + detail filling the full screen.
/// Same view tree for both — see RootView.
struct MainView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Sign Out") { Task { await auth.signOut() } }
                    }
                }
        } detail: {
            // NavigationSplitView pushes value-based destinations into the
            // *next* column — there is none after `detail`, so every
            // destination view's own NavigationLink(value:)/
            // .navigationDestination needs a NavigationStack here to push
            // into, rather than relying on the split view's column model.
            NavigationStack {
                switch selection {
                case .feed(let feed):
                    ArticlesListView(title: feed.title ?? "Articles") {
                        try await APIClient.shared.fetchArticles(feedId: feed.id)
                    }
                case .bookmarks:
                    ArticlesListView(title: "Bookmarks", emptyTitle: "No Bookmarks Yet") {
                        try await APIClient.shared.fetchArticles(state: "bookmarked")
                    }
                case .search:
                    SearchView()
                case .tags:
                    TagsListView()
                case .topics:
                    TopicsListView()
                case .discoverFeeds:
                    CatalogView()
                case .muteRules:
                    MuteRulesView()
                case .podcasts:
                    PodcastsView()
                case .youtube:
                    YouTubeChannelsView()
                case .sports:
                    SportsHomeView()
                case nil:
                    ContentUnavailableView("Select an Item", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }
}
