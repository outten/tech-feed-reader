import SwiftUI
import SafariServices

/// Phase 1's sign-up path (see design.md "Phase scoping"): a brand-new
/// account requires a passkey registration ceremony, which needs
/// Associated Domains to work natively — not set up yet. Rather than
/// build a custom login webview (and a JS bridge back into it), this
/// opens the real production /sign-up page in a system browser sheet.
/// That flow already ends by showing the user their one-time recovery
/// codes, which they then use to log in natively (see SignInView).
struct SafariSignUpView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
