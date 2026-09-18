import SwiftUI

struct ArticleDetailView: View {
    @State var article: Article
    @State private var allTags: [Tag] = []
    @State private var tappedLink: URL?
    @State private var isMuteKeywordPresented = false
    @State private var muteKeywordText = ""
    @State private var actionErrorMessage: String?
    @EnvironmentObject var audioPlayer: AudioPlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { tappedLink != nil }, set: { if !$0 { tappedLink = nil } })) {
            if let tappedLink {
                SafariView(url: tappedLink)
            }
        }
        .alert("Mute Keyword", isPresented: $isMuteKeywordPresented) {
            TextField("Keyword", text: $muteKeywordText)
                .textInputAutocapitalization(.never)
            Button("Mute") { Task { await muteKeyword() } }
            Button("Cancel", role: .cancel) { muteKeywordText = "" }
        } message: {
            Text("Hides articles whose title or body contains this word.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let playable = PlayableItem(article: article) {
                    Button {
                        if audioPlayer.currentItem?.id == playable.id {
                            audioPlayer.togglePlayPause()
                        } else {
                            audioPlayer.play(playable)
                        }
                    } label: {
                        Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                    }
                }
                Button {
                    Task { await toggleRead() }
                } label: {
                    Image(systemName: article.isRead ? "envelope.open.fill" : "envelope")
                }
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
        .task { await loadDetail() }
    }

    // MARK: - Header (metadata, feedback, mute, tags, summary)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heroImageURL = article.heroImageURL, article.youtubeEmbedURL == nil {
                AsyncImage(url: heroImageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipped()
            }

            metadataLine

            if let audioDurationText = article.audioDurationText {
                Text("Episode duration: \(audioDurationText)").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(article.feedback == 1 ? "👍 Boosted" : "👍") { Task { await toggleFeedback(1) } }
                    .buttonStyle(.bordered)
                    .tint(article.feedback == 1 ? .accentColor : .secondary)

                Button(article.feedback == -1 ? "👎 Demoted" : "👎") { Task { await toggleFeedback(-1) } }
                    .buttonStyle(.bordered)
                    .tint(article.feedback == -1 ? .accentColor : .secondary)

                if let author = article.author, !author.isEmpty {
                    Button("Mute author") { Task { await muteAuthor(author) } }
                        .buttonStyle(.bordered)
                }

                Button("Mute keyword") { isMuteKeywordPresented = true }
                    .buttonStyle(.bordered)
            }
            .font(.footnote)

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTags) { tag in
                            let applied = isApplied(tag)
                            Button {
                                Task { await toggleTag(tag) }
                            } label: {
                                Text(applied ? "\(tag.name) ✕" : "+ \(tag.name)")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(applied ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(applied ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let summaryText = article.summary?.llm.flatMap({ $0.isEmpty ? nil : $0 }) ?? article.summary?.extractive.flatMap({ $0.isEmpty ? nil : $0 }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary").font(.caption).foregroundStyle(.secondary)
                    Text(summaryText).font(.subheadline)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if let actionErrorMessage {
                Text(actionErrorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 6)
    }

    private var metadataLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metadataText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let sourceURL = URL(string: article.url) {
                Button {
                    tappedLink = sourceURL
                } label: {
                    Text("Source →")
                }
                .font(.subheadline)
            }
        }
    }

    private var metadataText: String {
        var parts: [String] = []
        if let feedName = article.feed?.title ?? article.feed?.url { parts.append(feedName) }
        if let author = article.author, !author.isEmpty { parts.append("by \(author)") }
        if let relative = article.relativePublishedTime { parts.append(relative) }
        if let minutes = article.readingTimeMinutes { parts.append("📖 \(minutes) min read") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Content (YouTube / HTML / plain text)

    private var content: some View {
        Group {
            if let embedURL = article.youtubeEmbedURL {
                VStack(spacing: 0) {
                    YouTubePlayerView(embedURL: embedURL)
                        .aspectRatio(16 / 9, contentMode: .fit)
                    ScrollView {
                        Text(article.contentText ?? "")
                            .padding()
                    }
                }
            } else if let html = article.contentHtml, !html.isEmpty {
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
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentItem?.id == article.uid && audioPlayer.isPlaying
    }

    private func isApplied(_ tag: Tag) -> Bool {
        article.tags?.contains { $0.id == tag.id } ?? false
    }

    // MARK: - Networking

    private func loadDetail() async {
        do {
            article = try await APIClient.shared.fetchArticle(uid: article.uid)
        } catch {
            // Keep showing the list-provided article; detail-only chrome
            // (summary/tags/feed/feedback) just won't appear.
        }
        allTags = (try? await APIClient.shared.fetchTags()) ?? []
        await markReadIfNeeded()
    }

    private func markReadIfNeeded() async {
        guard !article.isRead else { return }
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, read: true)
            article.read = 1
        } catch {
            // Best-effort — a failed request just leaves the article showing unread.
        }
    }

    private func toggleRead() async {
        let newValue = !article.isRead
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, read: newValue)
            article.read = newValue ? 1 : 0
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func toggleBookmarked() async {
        let newValue = !article.isBookmarked
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, bookmarked: newValue)
            article.bookmarked = newValue ? 1 : 0
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func toggleArchived() async {
        let newValue = !article.isArchived
        do {
            try await APIClient.shared.updateReadState(uid: article.uid, archived: newValue)
            article.archived = newValue ? 1 : 0
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func toggleFeedback(_ value: Int) async {
        let newValue = (article.feedback == value) ? 0 : value
        do {
            try await APIClient.shared.setArticleFeedback(uid: article.uid, value: newValue)
            article.feedback = newValue
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func muteAuthor(_ author: String) async {
        do {
            try await APIClient.shared.addMuteRule(kind: "author", value: author)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func muteKeyword() async {
        let value = muteKeywordText.trimmingCharacters(in: .whitespaces)
        muteKeywordText = ""
        guard !value.isEmpty else { return }
        do {
            try await APIClient.shared.addMuteRule(kind: "keyword", value: value)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func toggleTag(_ tag: Tag) async {
        do {
            if isApplied(tag) {
                try await APIClient.shared.removeTag(uid: article.uid, tagId: tag.id)
                article.tags?.removeAll { $0.id == tag.id }
            } else {
                try await APIClient.shared.applyTag(uid: article.uid, tagId: tag.id)
                article.tags = (article.tags ?? []) + [tag]
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}
