import SwiftUI
import WebKit

/// Embedded playback accepts HTTPS pages only. HTTPS subframes remain available
/// for the streaming providers' authentication and media integrations.
struct FilteredWebPlayer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        Task { @MainActor in
            await AdBlockingSettings.shared.configure(configuration.userContentController)
            guard url.scheme?.lowercased() == "https", url.host != nil,
                  url.user == nil, url.password == nil else { return }
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Playback URLs are immutable for each player instance.
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let destination = navigationAction.request.url,
                  let scheme = destination.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            // Reject HTTP, file, javascript, and custom-scheme navigations.
            // Keep about:blank for normal embedded player frame initialization.
            if scheme == "https", destination.host != nil,
               destination.user == nil, destination.password == nil {
                decisionHandler(.allow)
            } else if scheme == "about", destination.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
