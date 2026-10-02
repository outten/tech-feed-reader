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
///
/// Self-sizing: the web view's own scrolling is disabled and it reports
/// its rendered height back through `contentHeight` instead, so it can
/// sit inside the same outer ScrollView as the article's header
/// (ipad-article-header-scroll). A ResizeObserver (not a one-shot
/// measurement at didFinish) catches height changes from images that
/// finish loading/decoding after the initial parse, and from reflow on
/// rotation/width changes.
struct ArticleContentView: UIViewRepresentable {
    let html: String
    let onLinkTapped: (URL) -> Void
    @Binding var contentHeight: CGFloat

    private static let heightMessageHandlerName = "contentHeight"

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped, contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Self.heightMessageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styled = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font: -apple-system-body; padding: 12px; margin: 0; } img { max-width: 100%; height: auto; }</style>
        </head><body>\(html)
        <script>
        (function () {
            function reportHeight() {
                window.webkit.messageHandlers.\(Self.heightMessageHandlerName).postMessage(document.body.scrollHeight);
            }
            new ResizeObserver(reportHeight).observe(document.body);
            reportHeight();
        })();
        </script>
        </body></html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: heightMessageHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onLinkTapped: (URL) -> Void
        let contentHeight: Binding<CGFloat>

        init(onLinkTapped: @escaping (URL) -> Void, contentHeight: Binding<CGFloat>) {
            self.onLinkTapped = onLinkTapped
            self.contentHeight = contentHeight
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

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == ArticleContentView.heightMessageHandlerName,
                  let height = (message.body as? NSNumber)?.doubleValue else { return }
            DispatchQueue.main.async {
                self.contentHeight.wrappedValue = CGFloat(height)
            }
        }
    }
}
