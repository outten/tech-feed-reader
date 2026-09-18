import SwiftUI
import SafariServices

/// Generic in-app browser sheet (SFSafariViewController). Used for the
/// sign-up hand-off (SignInView) and for links tapped inside article
/// content (ArticleDetailView) — anything that should open a real web
/// page without leaving the app entirely.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
