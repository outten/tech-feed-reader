import SwiftUI
import WebKit

/// Renders an article's server-scrubbed content_html (see
/// app/articles_store.rb's content_scrubbed column — the server already
/// sanitizes this before it ever reaches a client). Not the auth
/// SafariView usage — this is a plain content renderer.
///
/// Links tapped inside the content are handed off via `onLinkTapped`
/// rather than let the WKWebView navigate itself: an embedded web view
/// following an arbitrary external link spins up new WebContent/GPU
/// processes that this app isn't entitled for, producing a cascade of
/// sandbox/process errors in the console (and a broken-looking page) —
/// the fix is to never let it navigate away from the article at all.
struct ArticleContentView: UIViewRepresentable {
    let html: String
    let onLinkTapped: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styled = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font: -apple-system-body; padding: 12px; } img { max-width: 100%; height: auto; }</style>
        </head><body>\(html)</body></html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLinkTapped: (URL) -> Void

        init(onLinkTapped: @escaping (URL) -> Void) {
            self.onLinkTapped = onLinkTapped
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // .other is the initial loadHTMLString call — allow it. Anything
            // the user taps (.linkActivated) gets handed off instead of
            // loaded in this same web view.
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            onLinkTapped(url)
        }
    }
}
