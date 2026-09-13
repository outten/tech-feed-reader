import SwiftUI

/// Persistent playback bar, shown above the tab/split view whenever an
/// episode is loaded — the native equivalent of the web mini-player that
/// survives Turbo navigation (this survives SwiftUI navigation instead,
/// since AudioPlayerViewModel lives above the NavigationSplitView).
struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayerViewModel

    var body: some View {
        if let item = player.currentItem {
            VStack(spacing: 4) {
                // Radio streams have no known duration — show an
                // indeterminate style instead of a 0%-stuck bar.
                if player.duration > 0 {
                    ProgressView(value: player.currentTime / player.duration)
                        .tint(.accentColor)
                } else {
                    ProgressView().tint(.accentColor)
                }
                HStack {
                    Text(item.title)
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
