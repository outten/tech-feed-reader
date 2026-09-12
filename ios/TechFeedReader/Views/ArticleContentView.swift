import SwiftUI
import WebKit

/// Renders an article's server-scrubbed content_html (see
/// app/articles_store.rb's content_scrubbed column — the server already
/// sanitizes this before it ever reaches a client). Not the auth
/// SafariSignUpView — this is a plain content renderer, no navigation
/// or JS bridge involved.
struct ArticleContentView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styled = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font: -apple-system-body; padding: 12px; } img { max-width: 100%; height: auto; }</style>
        </head><body>\(html)</body></html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }
}
