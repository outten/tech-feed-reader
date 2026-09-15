import SwiftUI

/// Persistent playback bar, shown above the tab/split view whenever an
/// episode is loaded — the native equivalent of the web mini-player that
/// survives Turbo navigation (this survives SwiftUI navigation instead,
/// since AudioPlayerViewModel lives above the NavigationSplitView).
struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayerViewModel
    @State private var scrubPosition: Double?

    var body: some View {
        if let item = player.currentItem {
            VStack(spacing: 4) {
                // Radio streams have no known duration — show an
                // indeterminate style instead of a 0%-stuck bar/scrubber.
                if player.duration > 0 {
                    Slider(
                        value: Binding(
                            get: { scrubPosition ?? player.currentTime },
                            set: { scrubPosition = $0 }
                        ),
                        in: 0...player.duration,
                        onEditingChanged: { editing in
                            if !editing, let scrubPosition {
                                player.seek(to: scrubPosition)
                                self.scrubPosition = nil
                            }
                        }
                    )
                    HStack {
                        Text(timeString(scrubPosition ?? player.currentTime)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(timeString(player.duration)).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().tint(.accentColor)
                }
                HStack {
                    Text(item.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if player.duration > 0 {
                        Button { player.skipBackward() } label: {
                            Image(systemName: "gobackward.15")
                        }
                        Button { player.skipForward() } label: {
                            Image(systemName: "goforward.30")
                        }
                        Menu {
                            ForEach(AudioPlayerViewModel.availableRates, id: \.self) { rate in
                                Button(rateLabel(rate)) { player.setPlaybackRate(rate) }
                            }
                        } label: {
                            Text(rateLabel(player.playbackRate))
                                .font(.caption)
                        }
                    }
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

    private func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%.2g×", rate)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
