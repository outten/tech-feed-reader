import SwiftUI

/// Phase 15 — a brand-new account has zero subscribed feeds, so the
/// Home dashboard would just be empty sections. Mirrors the web app's
/// `/` → `/welcome` redirect: show the topic-chip onboarding flow
/// instead until at least one feed is subscribed.
struct HomeGateView: View {
    @State private var hasCheckedFeeds = false
    @State private var hasFeeds = true

    var body: some View {
        Group {
            if !hasCheckedFeeds {
                ProgressView()
            } else if hasFeeds {
                HomeView()
            } else {
                WelcomeView(onSubscribed: { hasFeeds = true })
            }
        }
        .task {
            guard !hasCheckedFeeds else { return }
            // Fail open on a network error — HomeView surfaces the real
            // error instead of misrouting to Welcome.
            if let feeds = try? await APIClient.shared.fetchFeeds() {
                hasFeeds = !feeds.isEmpty
            }
            hasCheckedFeeds = true
        }
    }
}
