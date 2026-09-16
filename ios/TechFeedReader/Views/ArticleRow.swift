import SwiftUI

/// Shared row UI for every article list (feed, bookmarks, search, tag,
/// topic) — extracted so read/unread styling stays consistent everywhere
/// instead of copy-pasted per screen.
struct ArticleRow: View {
    let article: Article
    @EnvironmentObject var audioPlayer: AudioPlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
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
