import Foundation
import AVFoundation

/// Held at the app root (RootView), above the navigation stack, so
/// playback survives navigating between screens — the native
/// equivalent of the web app's persistent mini-player surviving Turbo
/// navigations. A single AVPlayer for the one episode playing at a time.
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published private(set) var currentArticle: Article?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    func play(_ article: Article) {
        guard let urlString = article.audioUrl, let url = URL(string: urlString) else { return }

        if currentArticle?.uid == article.uid, player != nil {
            player?.play()
            isPlaying = true
            return
        }

        removeTimeObserver()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentArticle = article
        duration = Double(article.audioDurationSeconds ?? 0)

        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        try? AVAudioSession.sharedInstance().setActive(true)
        newPlayer.play()
        isPlaying = true
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func stop() {
        player?.pause()
        removeTimeObserver()
        player = nil
        currentArticle = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }
}
