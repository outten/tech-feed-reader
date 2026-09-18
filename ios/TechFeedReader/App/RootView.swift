import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var audioPlayer: AudioPlayerViewModel

    var body: some View {
        // NavigationSplitView adapts on its own: a single column that
        // behaves like a nav stack on iPhone, sidebar + detail filling
        // the full screen on iPad — no separate iPhone/iPad view needed.
        if auth.isSignedIn {
            VStack(spacing: 0) {
                MainView()
                // Above (not inside) the split view so it stays visible
                // and playback keeps going no matter what's selected.
                MiniPlayerView(player: audioPlayer)
            }
        } else {
            SignInView()
        }
    }
}
