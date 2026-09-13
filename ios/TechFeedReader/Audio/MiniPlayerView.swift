import SwiftUI

/// Persistent playback bar, shown above the tab/split view whenever an
/// episode is loaded — the native equivalent of the web mini-player that
/// survives Turbo navigation (this survives SwiftUI navigation instead,
/// since AudioPlayerViewModel lives above the NavigationSplitView).
struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayerViewModel

    var body: some View {
        if let article = player.currentArticle {
            VStack(spacing: 4) {
                ProgressView(value: player.duration > 0 ? player.currentTime / player.duration : 0)
                    .tint(.accentColor)
                HStack {
                    Text(article.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }
}
