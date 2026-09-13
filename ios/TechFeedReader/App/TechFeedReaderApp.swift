import SwiftUI

@main
struct TechFeedReaderApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var audioPlayer = AudioPlayerViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(audioPlayer)
        }
    }
}
