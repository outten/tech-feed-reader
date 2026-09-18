import SwiftUI

/// Phase 14 — the sidebar's default landing item, mirroring the web
/// app's "/" What's On Today dashboard (see design.md for what's
/// deliberately thinner here: no YouTube-fallback padding, no
/// continue-watching).
struct HomeView: View {
    @State private var home: HomeResponse?
    @State private var continueListening: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if let home {
                Section {
                    HStack {
                        statTile("Unread", home.stats.unread)
                        statTile("Bookmarks", home.stats.bookmarks)
                        statTile("Articles", home.stats.articles)
                    }
                }

                if !continueListening.isEmpty {
                    Section("Continue Listening") {
                        ForEach(continueListening) { article in
                            NavigationLink(value: article) {
                                ArticleRow(article: article)
                            }
                        }
                    }
                }

                if !home.liveMatches.isEmpty {
                    Section("Live") {
                        ForEach(home.liveMatches) { MatchRow(match: $0) }
                    }
                }
                if !home.todayMatches.isEmpty {
                    Section("Today's Matches") {
                        ForEach(home.todayMatches) { MatchRow(match: $0) }
                    }
                }
                if !home.todayReading.isEmpty {
                    Section("To Read Today") {
                        ForEach(home.todayReading) { article in
                            NavigationLink(value: article) { ArticleRow(article: article) }
                        }
                    }
                }
                if !home.todayListening.isEmpty {
                    Section("To Listen Today") {
                        ForEach(home.todayListening) { article in
                            NavigationLink(value: article) { ArticleRow(article: article) }
                        }
                    }
                }
                if !home.todayWatching.isEmpty {
                    Section("To Watch Today") {
                        ForEach(home.todayWatching) { article in
                            NavigationLink(value: article) { ArticleRow(article: article) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Home")
        .navigationDestination(for: Article.self) { article in
            ArticleDetailView(article: article)
        }
        .overlay {
            if isLoading && home == nil { ProgressView() }
            if !isLoading, let home, nothingToday(home) {
                ContentUnavailableView("Nothing New Today", systemImage: "sun.max")
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func nothingToday(_ home: HomeResponse) -> Bool {
        continueListening.isEmpty && home.liveMatches.isEmpty && home.todayMatches.isEmpty &&
            home.todayReading.isEmpty && home.todayListening.isEmpty && home.todayWatching.isEmpty
    }

    private func statTile(_ label: String, _ value: Int) -> some View {
        VStack {
            Text("\(value)").font(.title2).bold()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            home = try await APIClient.shared.fetchHome()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        let stored = AudioPlayerViewModel.storedPositions()
        var resolved: [Article] = []
        for entry in stored {
            if let article = try? await APIClient.shared.fetchArticle(uid: entry.uid) {
                resolved.append(article)
            }
        }
        continueListening = resolved
    }
}
