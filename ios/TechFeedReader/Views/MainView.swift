import SwiftUI

/// iPhone: NavigationSplitView collapses to a single navigable column.
/// iPad: sidebar (Library + Feeds) + detail filling the full screen.
/// Same view tree for both — see RootView.
struct MainView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var selection: SidebarItem? = .home

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
                case .home:
                    HomeGateView()
                case .allArticles:
                    ReadingRiverView()
                case .feed(let feed):
                    FeedArticlesView(feed: feed)
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
                case .stocks:
                    StocksHomeView()
                case .comics:
                    ArticlesListView(title: "Comics", emptyTitle: "No Comics Yet") {
                        try await APIClient.shared.fetchArticles(topic: "humor")
                    }
                case .npr:
                    ArticlesListView(title: "NPR", emptyTitle: "No NPR Articles Yet") {
                        try await APIClient.shared.fetchArticles(topic: "npr")
                    }
                case .pbs:
                    ArticlesListView(title: "PBS", emptyTitle: "No PBS Articles Yet") {
                        try await APIClient.shared.fetchArticles(topic: "pbs")
                    }
                case .radio:
                    RadioStationsView()
                case .triage:
                    TriageHomeView()
                case .digests:
                    DigestsHomeView()
                case .account:
                    AccountView()
                case .busMode:
                    BusModeView()
                case .lucky:
                    ArticlesListView(title: "I Feel Lucky", emptyTitle: "Nothing To Show") {
                        try await APIClient.shared.fetchLucky()
                    }
                case nil:
                    ContentUnavailableView("Select an Item", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }
}
