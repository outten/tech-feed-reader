import Foundation
import AVFoundation
import MediaPlayer

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
///
/// Phase 13 — player parity with the web mini-player: seek/scrub,
/// ±15s/±30s skip, playback speed, resume-from-last-position (stored
/// in UserDefaults, matching the web app's localStorage — both are
/// local-only, not synced through the account), and
/// MPNowPlayingInfoCenter/MPRemoteCommandCenter so backgrounded audio
/// gets lock-screen/CarPlay/AirPods controls.
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published private(set) var currentItem: PlayableItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackRate: Float = 1.0

    static let skipBackSeconds: Double = 15
    static let skipForwardSeconds: Double = 30
    static let availableRates: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]

    /// Matches the web app's RESUME_TAIL_S — don't resume into the last
    /// 30s of an episode (it's effectively finished).
    private static let resumeTailSeconds: Double = 30
    private static let positionKeyPrefix = "tfr.podcast.position."
    private static let saveThrottleSeconds: TimeInterval = 5

    /// Phase 14 — "Continue Listening" reads locally-stored positions
    /// directly, mirroring the web app's `continue-progress.js` (which
    /// scans `localStorage` for the same key prefix). Skips near-zero
    /// positions as noise, matching the web's `MIN_SECONDS`.
    static func storedPositions(minSeconds: Double = 5, maxItems: Int = 6) -> [(uid: String, seconds: Double)] {
        UserDefaults.standard.dictionaryRepresentation()
            .compactMap { key, value -> (String, Double)? in
                guard key.hasPrefix(positionKeyPrefix), let seconds = value as? Double, seconds >= minSeconds else { return nil }
                return (String(key.dropFirst(positionKeyPrefix.count)), seconds)
            }
            .prefix(maxItems)
            .map { (uid: $0.0, seconds: $0.1) }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var lastPositionSaveAt: Date = .distantPast

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        configureRemoteCommands()
    }

    func play(_ item: PlayableItem) {
        if currentItem?.id == item.id, player != nil {
            player?.play()
            isPlaying = true
            updateNowPlayingInfo()
            return
        }

        savePosition()
        removeTimeObserver()
        let newPlayer = AVPlayer(playerItem: AVPlayerItem(url: item.url))
        newPlayer.rate = playbackRate
        player = newPlayer
        currentItem = item
        duration = Double(item.durationSeconds ?? 0)
        currentTime = 0

        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            self.updateNowPlayingInfo()
            self.throttledSavePosition()
        }

        try? AVAudioSession.sharedInstance().setActive(true)

        if let resumeSeconds = storedPosition(for: item), resumeSeconds < duration - Self.resumeTailSeconds {
            newPlayer.seek(to: CMTime(seconds: resumeSeconds, preferredTimescale: 1))
            currentTime = resumeSeconds
        }

        newPlayer.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            savePosition()
        } else {
            player.playImmediately(atRate: playbackRate)
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 1))
        currentTime = clamped
        updateNowPlayingInfo()
        savePosition()
    }

    func skipBackward() { seek(to: currentTime - Self.skipBackSeconds) }
    func skipForward() { seek(to: currentTime + Self.skipForwardSeconds) }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player?.rate = rate }
        updateNowPlayingInfo()
    }

    func stop() {
        savePosition()
        player?.pause()
        removeTimeObserver()
        player = nil
        currentItem = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    // MARK: - Resume position (UserDefaults, matches the web app's localStorage)

    private func storedPosition(for item: PlayableItem) -> Double? {
        let value = UserDefaults.standard.double(forKey: Self.positionKeyPrefix + item.id)
        return value > 0 ? value : nil
    }

    private func throttledSavePosition() {
        guard Date().timeIntervalSince(lastPositionSaveAt) >= Self.saveThrottleSeconds else { return }
        savePosition()
    }

    private func savePosition() {
        guard let currentItem, duration > 0 else { return }
        lastPositionSaveAt = Date()
        UserDefaults.standard.set(currentTime, forKey: Self.positionKeyPrefix + currentItem.id)
    }

    // MARK: - Now Playing / remote commands

    private func updateNowPlayingInfo() {
        guard let currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player, !self.isPlaying else { return .commandFailed }
            player.playImmediately(atRate: self.playbackRate)
            self.isPlaying = true
            self.updateNowPlayingInfo()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.player?.pause()
            self.isPlaying = false
            self.savePosition()
            self.updateNowPlayingInfo()
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBackSeconds)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForwardSeconds)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }
}
