import SwiftUI

struct ArticleDetailView: View {
    @State var article: Article
    @State private var tappedLink: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let html = article.contentHtml, !html.isEmpty {
                // WKWebView reports no intrinsic content size in SwiftUI —
                // without an explicit frame it collapses to zero height and
                // renders nothing, even though loadHTMLString succeeded.
                ArticleContentView(html: html) { url in tappedLink = url }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(article.contentText ?? "")
                        .padding()
                }
            }
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { tappedLink != nil }, set: { if !$0 { tappedLink = nil } })) {
            if let tappedLink {
                SafariView(url: tappedLink)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await toggleBookmarked() }
                } label: {
                    Image(systemName: article.isBookmarked ? "bookmark.fill" : "bookmark")
                }
                Button {
                    Task { await toggleArchived() }
                } label: {
                    Image(systemName: article.isArchived ? "archivebox.fill" : "archivebox")
                }
            }
        }
        .task { await markRead() }
    }

    private func markRead() async {
        guard !article.isRead else { return }
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, read: true)
            article.read = 1
        } catch {
            // Best-effort — a failed request just leaves the article showing unread.
        }
    }

    private func toggleBookmarked() async {
        let newValue = !article.isBookmarked
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, bookmarked: newValue)
            article.bookmarked = newValue ? 1 : 0
        } catch {
            // Best-effort — UI just keeps showing the prior state.
        }
    }

    private func toggleArchived() async {
        let newValue = !article.isArchived
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, archived: newValue)
            article.archived = newValue ? 1 : 0
        } catch {
            // Best-effort — UI just keeps showing the prior state.
        }
    }
}
