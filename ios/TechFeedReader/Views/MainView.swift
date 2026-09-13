import SwiftUI

/// iPhone: NavigationSplitView collapses to a single navigable column.
/// iPad: sidebar (feeds) + detail (articles/article) filling the full
/// screen. Same view tree for both — see RootView.
struct MainView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var selectedFeed: Feed?

    var body: some View {
        NavigationSplitView {
            FeedListView(selectedFeed: $selectedFeed)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Sign Out") { Task { await auth.signOut() } }
                    }
                }
        } detail: {
            // NavigationSplitView pushes value-based destinations into the
            // *next* column — there is none after `detail`, so
            // ArticleListView's NavigationLink(value:)/.navigationDestination
            // needs its own NavigationStack to push ArticleDetailView into,
            // rather than relying on the split view's column model.
            NavigationStack {
                if let selectedFeed {
                    ArticleListView(feed: selectedFeed)
                } else {
                    ContentUnavailableView("Select a Feed", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }
}
