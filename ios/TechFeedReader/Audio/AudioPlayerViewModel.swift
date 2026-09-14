import Foundation
import AVFoundation

/// Anything the shared player can play — a podcast episode (Article)
/// or a radio station (a live stream with no known duration). `id`
/// distinguishes "already playing this" from "switch to something new".
struct PlayableItem: Equatable {
    let id: String
    let title: String
    let url: URL
    let durationSeconds: Int?

    init?(article: Article) {
        guard let urlString = article.audioUrl, let url = URL(string: urlString) else { return nil }
        self.id = article.uid
        self.title = article.title
        self.url = url
        self.durationSeconds = article.audioDurationSeconds
    }

    init?(radioStation: RadioStation) {
        guard let url = URL(string: radioStation.streamUrl) else { return nil }
        self.id = "radio-\(radioStation.id)"
        self.title = radioStation.name
        self.url = url
        self.durationSeconds = nil
    }
}

/// Held at the app root (RootView), above the navigation stack, so
/// playback survives navigating between screens — the native
/// equivalent of the web app's persistent mini-player surviving Turbo
/// navigations. A single AVPlayer for the one item playing at a time.
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published private(set) var currentItem: PlayableItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    func play(_ item: PlayableItem) {
        if currentItem?.id == item.id, player != nil {
            player?.play()
            isPlaying = true
            return
        }

        removeTimeObserver()
        let newPlayer = AVPlayer(playerItem: AVPlayerItem(url: item.url))
        player = newPlayer
        currentItem = item
        duration = Double(item.durationSeconds ?? 0)

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
        currentItem = nil
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
