import SwiftUI

/// Shared row UI for every article list (feed, bookmarks, search, tag,
/// topic, Podcasts, Comics, NPR, PBS) — extracted so read/unread styling
/// and the image-led card look stay consistent everywhere instead of
/// copy-pasted per screen. Mirrors the web app's `.podcast-card`
/// (thumbnail + meta line + title + excerpt), which those web pages
/// already share (Phase 16).
struct ArticleRow: View {
    let article: Article
    @EnvironmentObject var audioPlayer: AudioPlayerViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumbnailURL = article.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let publishedAt = article.publishedAt {
                        Text(publishedAt)
                    }
                    if let duration = article.audioDurationText {
                        Text("·")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let excerpt = article.excerptText {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let playable = PlayableItem(article: article) {
                Spacer(minLength: 0)
                Button {
                    if audioPlayer.currentItem?.id == playable.id {
                        audioPlayer.togglePlayPause()
                    } else {
                        audioPlayer.play(playable)
                    }
                } label: {
                    Image(systemName: isCurrentlyPlaying(playable) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                // .borderless so tapping the button plays the episode
                // instead of also triggering the row's NavigationLink.
                .buttonStyle(.borderless)
            }
        }
    }

    private func isCurrentlyPlaying(_ playable: PlayableItem) -> Bool {
        audioPlayer.currentItem?.id == playable.id && audioPlayer.isPlaying
    }
}
