import SwiftUI
import WebKit

/// Embeds a single YouTube video via the standard iframe-embed URL —
/// the native-app equivalent of the web article page's iframe player.
/// Playback stays inside YouTube's own player (not this app's audio
/// pipeline), so no WKNavigationDelegate link-interception is needed
/// here the way ArticleContentView needs it for arbitrary article links.
struct YouTubePlayerView: UIViewRepresentable {
    let embedURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: embedURL))
    }
}
