import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        // NavigationSplitView adapts on its own: a single column that
        // behaves like a nav stack on iPhone, sidebar + detail filling
        // the full screen on iPad — no separate iPhone/iPad view needed.
        if auth.isSignedIn {
            MainView()
        } else {
            SignInView()
        }
    }
}
